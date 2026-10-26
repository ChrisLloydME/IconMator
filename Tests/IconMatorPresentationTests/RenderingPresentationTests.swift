import Foundation
import IconConversionCore
import Testing
@testable import IconMatorPresentation

private actor RecordingConverter: IconConversionPerforming {
    private var optionsLog: [IconRenderOptions] = []
    private let previewData: Data
    private let gate: ConversionGate?

    init(previewData: Data, gate: ConversionGate? = nil) {
        self.previewData = previewData
        self.gate = gate
    }

    func convert(input: URL, destination: URL, tools: DeveloperTools, options: IconRenderOptions,
                 exportPNG: Bool, overwrite: Bool,
                 progress: @escaping @Sendable (ConversionStage) async -> Void) async throws -> ConversionResult {
        optionsLog.append(options)
        await progress(.rendering)
        if let gate { await gate.wait() }
        return ConversionResult(icns: destination,
            png: exportPNG ? destination.deletingPathExtension().appendingPathExtension("png") : nil,
            environment: "Rendering: \(options.generation.displayName); Appearance: \(options.appearance.displayName)",
            diagnostics: "mock diagnostics",
            previewPNG: previewData, options: options,
            rendition: options.appearance.composerRendition?.rawValue ?? "",
            backend: "mock", composerVersion: nil)
    }

    func preview(input: URL, options: IconRenderOptions, tools: DeveloperTools) async throws -> Data {
        previewData
    }

    func recordedOptions() -> [IconRenderOptions] { optionsLog }
}

private actor PreviewGate {
    private struct Request: Hashable {
        let options: IconRenderOptions
        let identity: String
    }

    private var requests: [Request] = []
    private var continuations: [Request: CheckedContinuation<Data, Never>] = [:]

    func wait(options: IconRenderOptions, identity: String) async -> Data {
        let request = Request(options: options, identity: identity)
        requests.append(request)
        return await withCheckedContinuation { continuations[request] = $0 }
    }

    func requested(_ options: IconRenderOptions, identity: String? = nil) -> Bool {
        requests.contains { $0.options == options && (identity == nil || $0.identity == identity) }
    }

    func requestCount() -> Int { requests.count }

    func requestCount(_ options: IconRenderOptions, identity: String) -> Int {
        requests.filter { $0.options == options && $0.identity == identity }.count
    }

    func release(_ options: IconRenderOptions, identity: String, data: Data) {
        continuations.removeValue(forKey: Request(options: options, identity: identity))?.resume(returning: data)
    }
}

private actor ConversionGate {
    private var started = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func hasStarted() -> Bool { started }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor struct RenderingPresentationTests {
    @Test func generationChangeRequestsNewPreviewAndLateResultCannotOverwrite() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = try makeIcon("Generation 空格.icon", in: workspace.url)
        let gate = PreviewGate()
        let model = ConversionViewModel(externalToolsPermitted: true, previewRenderer: { _, options, tools in
            await gate.wait(options: options, identity: tools.identity)
        })
        let tools = fixtureTools()
        model.tools = tools
        model.importFiles([icon])
        let first = IconRenderOptions(generation: .macOS27, appearance: .default)
        let second = IconRenderOptions(generation: .macOS26, appearance: .default)
        #expect(await waitForRequest(gate, first, tools.identity))
        model.generation = .macOS26
        #expect(await waitForRequest(gate, second, tools.identity))

        // Deliver the current generation first, then let the obsolete generation
        // arrive late. The late result must be rejected.
        await gate.release(second, identity: tools.identity, data: Data("gen26".utf8))
        await waitForPreview(model)
        await gate.release(first, identity: tools.identity, data: Data("gen27".utf8))
        await settle()
        #expect(model.selectedJob?.preview == Data("gen26".utf8))
        #expect(model.selectedJob?.previewOptions == second)
        model.stopAllTasks()
    }

    @Test func rapidGenerationAndAppearanceChangesKeepOnlyTheLatestResult() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = try makeIcon("Rapid Options.icon", in: workspace.url)
        let gate = PreviewGate()
        let model = ConversionViewModel(externalToolsPermitted: true, previewRenderer: { _, options, tools in
            await gate.wait(options: options, identity: tools.identity)
        })
        let tools = fixtureTools()
        model.tools = tools
        model.importFiles([icon])
        let initial = IconRenderOptions(generation: .macOS27, appearance: .default)
        let middle = IconRenderOptions(generation: .macOS26, appearance: .dark)
        let latest = IconRenderOptions(generation: .macOS27, appearance: .mono)
        #expect(await waitForRequest(gate, initial, tools.identity))
        model.generation = .macOS26
        model.appearance = .dark
        #expect(await waitForRequest(gate, middle, tools.identity))
        model.generation = .macOS27
        model.appearance = .mono
        #expect(await waitForRequest(gate, latest, tools.identity))

        await gate.release(middle, identity: tools.identity, data: Data("middle".utf8))
        await gate.release(initial, identity: tools.identity, data: Data("initial".utf8))
        await gate.release(latest, identity: tools.identity, data: Data("latest".utf8))
        await waitForPreview(model)

        #expect(model.selectedJob?.preview == Data("latest".utf8))
        #expect(model.selectedJob?.previewOptions == latest)
        model.stopAllTasks()
    }

    @Test func thumbnailOptionChecksUseTheSameCompleteRequest() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let first = try makeIcon("First.icon", in: workspace.url)
        let second = try makeIcon("Second.icon", in: workspace.url)
        let gate = PreviewGate()
        let model = ConversionViewModel(externalToolsPermitted: true, previewRenderer: { _, options, tools in
            await gate.wait(options: options, identity: tools.identity)
        })
        let tools = fixtureTools()
        model.tools = tools
        model.appearance = .dark
        model.importFiles([first, second])
        let dark27 = IconRenderOptions(generation: .macOS27, appearance: .dark)
        let dark26 = IconRenderOptions(generation: .macOS26, appearance: .dark)
        #expect(await waitForRequest(gate, dark27, tools.identity))
        await gate.release(dark27, identity: tools.identity, data: Data("first-dark27".utf8))
        await waitForPreview(model)

        // Cache the second thumbnail under the same complete request.
        model.selection = model.jobs[0].id
        let previousRequests = await gate.requestCount(dark27, identity: tools.identity)
        model.selection = model.jobs[1].id
        #expect(await waitForRequest(gate, dark27, tools.identity, minimumCount: previousRequests + 1))
        await gate.release(dark27, identity: tools.identity, data: Data("second-dark27".utf8))
        await waitForPreview(model)
        #expect(model.jobs[0].previewOptions == dark27)
        #expect(model.jobs[1].previewOptions == dark27)

        // A generation change invalidates both thumbnails and the large preview.
        model.generation = .macOS26
        #expect(model.jobs.allSatisfy { $0.preview == nil && $0.previewOptions == nil })
        #expect(await waitForRequest(gate, dark26, tools.identity))
        await gate.release(dark26, identity: tools.identity, data: Data("second-dark26".utf8))
        await waitForPreview(model)
        #expect(model.selectedJob?.preview == Data("second-dark26".utf8))
        #expect(model.selectedJob?.previewOptions == dark26)
        #expect(model.jobs[0].preview == nil)
        model.stopAllTasks()
    }

    @Test func conversionUsesCapturedOptionsAndOptionChangeClearsOutput() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = try makeIcon("Convert.icon", in: workspace.url)
        let converter = RecordingConverter(previewData: Data("converted".utf8))
        let model = ConversionViewModel(externalToolsPermitted: true, converter: converter,
            previewRenderer: { _, _, _ in Data("preview".utf8) })
        model.tools = fixtureTools()
        model.destination = workspace.url
        model.generation = .macOS26
        model.appearance = .dark
        model.importFiles([icon])
        await waitForPreview(model)

        model.startConversion()
        await waitForConversion(model)

        #expect(await converter.recordedOptions() == [IconRenderOptions(generation: .macOS26, appearance: .dark)])
        #expect(model.selectedJob?.outputOptions == IconRenderOptions(generation: .macOS26, appearance: .dark))
        #expect(model.selectedJob?.status == "Exported and verified")
        #expect(model.revealTarget != nil)

        model.appearance = .mono
        #expect(model.selectedJob?.output == nil)
        #expect(model.selectedJob?.outputOptions == nil)
        #expect(model.selectedJob?.status == "Ready")
        #expect(model.revealTarget == nil)
        #expect(model.selectedJob?.preview == nil)

        model.generation = .macOS27
        #expect(model.selectedJob?.output == nil)
        #expect(model.revealTarget == nil)
        model.stopAllTasks()
    }

    @Test func batchUsesCapturedOptionsWhileControlsCannotChange() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let first = try makeIcon("Batch One.icon", in: workspace.url)
        let second = try makeIcon("Batch Two.icon", in: workspace.url)
        let gate = ConversionGate()
        let converter = RecordingConverter(previewData: Data("converted".utf8), gate: gate)
        let model = ConversionViewModel(externalToolsPermitted: true, converter: converter,
            previewRenderer: { _, _, _ in Data("preview".utf8) })
        model.tools = fixtureTools()
        model.destination = workspace.url
        model.generation = .macOS26
        model.appearance = .dark
        model.importFiles([first, second])
        await waitForPreview(model)
        model.startConversion()
        for _ in 0..<400 {
            if await gate.hasStarted() { break }
            await Task.yield()
        }
        #expect(await gate.hasStarted())
        // These assignments are ignored while a batch is active.
        model.generation = .macOS27
        model.appearance = .mono
        #expect(model.renderOptions == IconRenderOptions(generation: .macOS26, appearance: .dark))
        await gate.release()
        await waitForConversion(model)

        let expected = IconRenderOptions(generation: .macOS26, appearance: .dark)
        #expect(await converter.recordedOptions() == [expected, expected])
        #expect(model.jobs.allSatisfy { $0.outputOptions == expected })
        #expect(model.jobs.allSatisfy { $0.status == "Exported and verified" })
        model.stopAllTasks()
    }

    @Test func unavailableCombinationsDisableConversionWithSpecificReasons() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = try makeIcon("Tools.icon", in: workspace.url)
        let missingModel = ConversionViewModel(externalToolsPermitted: true,
            previewRenderer: { _, _, _ in Data("preview".utf8) })
        missingModel.tools = fixtureTools(composer: false)
        missingModel.destination = workspace.url
        missingModel.importFiles([icon])
        #expect(missingModel.canConvert)
        #expect(missingModel.renderIssue == nil)
        missingModel.generation = .macOS26
        #expect(missingModel.renderIssue?.contains("Icon Composer") == true)
        #expect(!missingModel.canConvert)
        missingModel.generation = .macOS27
        missingModel.appearance = .mono
        #expect(missingModel.renderIssue?.contains("Icon Composer") == true)
        #expect(!missingModel.canConvert)

        let noSelectionModel = ConversionViewModel(externalToolsPermitted: true,
            previewRenderer: { _, _, _ in Data("preview".utf8) })
        noSelectionModel.tools = fixtureTools(supportsGenerationSelection: false)
        noSelectionModel.destination = workspace.url
        noSelectionModel.importFiles([icon])
        noSelectionModel.generation = .macOS26
        #expect(noSelectionModel.renderIssue?.contains("--design-generation") == true)
        #expect(!noSelectionModel.canConvert)
        noSelectionModel.generation = .macOS27
        noSelectionModel.appearance = .default
        #expect(noSelectionModel.renderIssue == nil)
        #expect(noSelectionModel.canConvert)

        let unreadableModel = ConversionViewModel(externalToolsPermitted: true,
            previewRenderer: { _, _, _ in Data("preview".utf8) })
        unreadableModel.tools = fixtureTools(composerInfoUnreadable: true)
        unreadableModel.destination = workspace.url
        unreadableModel.importFiles([icon])
        unreadableModel.generation = .macOS26
        #expect(unreadableModel.renderIssue?.contains("version could not be read") == true)
        #expect(!unreadableModel.canConvert)
        unreadableModel.stopAllTasks()
        missingModel.stopAllTasks()
        noSelectionModel.stopAllTasks()
    }

    @Test func toolIdentityChangeInvalidatesPreviewAndRejectsLateResult() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = try makeIcon("Identity.icon", in: workspace.url)
        let gate = PreviewGate()
        let model = ConversionViewModel(externalToolsPermitted: true, previewRenderer: { _, options, tools in
            await gate.wait(options: options, identity: tools.identity)
        })
        let firstTools = fixtureTools(composerVersion: "27.1", composerBuild: "129")
        let secondTools = fixtureTools(composerVersion: "27.2", composerBuild: "130")
        model.tools = firstTools
        model.importFiles([icon])
        let options = IconRenderOptions(generation: .macOS27, appearance: .dark)
        model.appearance = .dark
        #expect(await waitForRequest(gate, options, firstTools.identity))
        model.tools = secondTools
        #expect(await waitForRequest(gate, options, secondTools.identity))
        await gate.release(options, identity: secondTools.identity, data: Data("new-tool".utf8))
        await waitForPreview(model)
        await gate.release(options, identity: firstTools.identity, data: Data("old-tool".utf8))
        await settle()
        #expect(model.selectedJob?.preview == Data("new-tool".utf8))
        #expect(model.selectedJob?.previewToolIdentity == secondTools.identity)
        model.stopAllTasks()
    }

    private func waitForRequest(_ gate: PreviewGate, _ options: IconRenderOptions, _ identity: String,
                                minimumCount: Int = 1) async -> Bool {
        for _ in 0..<600 {
            if await gate.requestCount(options, identity: identity) >= minimumCount { return true }
            await Task.yield()
        }
        return false
    }

    private func waitForPreview(_ model: ConversionViewModel) async {
        for _ in 0..<600 {
            if !model.isPreviewing, model.selectedJob?.preview != nil { return }
            await Task.yield()
        }
    }

    private func waitForConversion(_ model: ConversionViewModel) async {
        for _ in 0..<800 {
            if !model.isConverting, model.jobs.allSatisfy({ $0.output != nil || $0.status == "Failed" }) { return }
            await Task.yield()
        }
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func makeIcon(_ name: String, in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try Data("{\"groups\":[]}".utf8).write(to: url.appendingPathComponent("icon.json"))
        return url
    }

    private func fixtureTools(composer: Bool = true, host: String = "27.0.1 (26A434)",
                              composerVersion: String = "27.1", composerBuild: String = "129",
                              supportsGenerationSelection: Bool = true,
                              composerInfoUnreadable: Bool = false) -> DeveloperTools {
        let interface = ComposerInterfaceCapabilities(exportImage: true, rendition: true,
            designGeneration: supportsGenerationSelection)
        let info: ComposerToolInfo? = composer && !composerInfoUnreadable
            ? ComposerToolInfo(path: "/usr/bin/true", shortVersion: composerVersion,
                buildVersion: composerBuild, interface: interface)
            : nil
        return DeveloperTools(developerDirectory: URL(fileURLWithPath: "/fixture/Xcode/Contents/Developer"),
            xcodebuild: URL(fileURLWithPath: "/fixture/xcodebuild"),
            actool: URL(fileURLWithPath: "/fixture/actool"),
            clang: URL(fileURLWithPath: "/fixture/clang"),
            sdk: URL(fileURLWithPath: "/fixture/SDK"), sdkVersion: "27.0",
            iconutil: URL(fileURLWithPath: "/usr/bin/iconutil"),
            composerTool: composer ? URL(fileURLWithPath: "/usr/bin/true") : nil,
            composerInfo: info,
            composerIssue: composer && composerInfoUnreadable
                ? "The Icon Composer renderer version could not be read: /usr/bin/true."
                : nil,
            xcodeVersion: "fixture", operatingSystem: host)
    }
}
