import Foundation
import IconConversionCore
import Testing
@testable import IconMatorPresentation

private actor RecordingConverter: IconConversionPerforming {
    private var appearances: [IconAppearance] = []
    private let previewData: Data

    init(previewData: Data) { self.previewData = previewData }

    func convert(input: URL, destination: URL, tools: DeveloperTools, appearance: IconAppearance,
                 exportPNG: Bool, overwrite: Bool,
                 progress: @escaping @Sendable (ConversionStage) async -> Void) async throws -> ConversionResult {
        appearances.append(appearance)
        await progress(.rendering)
        return ConversionResult(icns: destination,
            png: exportPNG ? destination.deletingPathExtension().appendingPathExtension("png") : nil,
            environment: "mock \(appearance.displayName)", diagnostics: "mock diagnostics",
            previewPNG: previewData, appearance: appearance,
            rendition: appearance.composerRendition?.rawValue ?? "", backend: "mock")
    }

    func preview(input: URL, appearance: IconAppearance, tools: DeveloperTools) async throws -> Data {
        previewData
    }

    func recordedAppearances() -> [IconAppearance] { appearances }
}

private actor PreviewGate {
    private var continuations: [IconAppearance: CheckedContinuation<Data, Never>] = [:]
    private var requests: Set<IconAppearance> = []

    func wait(_ appearance: IconAppearance) async -> Data {
        requests.insert(appearance)
        return await withCheckedContinuation { continuations[appearance] = $0 }
    }

    func requested(_ appearance: IconAppearance) -> Bool { requests.contains(appearance) }

    func release(_ appearance: IconAppearance, data: Data) {
        continuations.removeValue(forKey: appearance)?.resume(returning: data)
    }
}

@MainActor struct AppearancePresentationTests {
    @Test func lateDefaultPreviewCannotReplaceDarkPreview() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = try makeIcon("Preview 空格.icon", in: workspace.url)
        let gate = PreviewGate()
        let model = ConversionViewModel(externalToolsPermitted: true, previewRenderer: { _, appearance, _ in
            await gate.wait(appearance)
        })
        model.tools = try fixtureTools(composer: true)
        model.importFiles([icon])
        #expect(await waitForRequest(gate, .default))
        model.appearance = .dark
        #expect(await waitForRequest(gate, .dark))

        await gate.release(.default, data: Data("default".utf8))
        await gate.release(.dark, data: Data("dark".utf8))
        await waitForPreview(model)

        #expect(model.selectedJob?.preview == Data("dark".utf8))
        #expect(model.selectedJob?.previewAppearance == .dark)
        #expect(model.selectedJob?.preview != Data("default".utf8))
        model.stopAllTasks()
    }

    @Test func rapidAppearanceSwitchingKeepsOnlyTheLatestResult() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = try makeIcon("Rapid.icon", in: workspace.url)
        let gate = PreviewGate()
        let model = ConversionViewModel(externalToolsPermitted: true, previewRenderer: { _, appearance, _ in
            await gate.wait(appearance)
        })
        model.tools = try fixtureTools(composer: true)
        model.importFiles([icon])
        #expect(await waitForRequest(gate, .default))
        model.appearance = .dark
        #expect(await waitForRequest(gate, .dark))
        model.appearance = .mono
        #expect(await waitForRequest(gate, .mono))

        // Deliver the obsolete results first, then the current one.
        await gate.release(.dark, data: Data("dark".utf8))
        await gate.release(.default, data: Data("default".utf8))
        await gate.release(.mono, data: Data("mono".utf8))
        await waitForPreview(model)

        #expect(model.selectedJob?.preview == Data("mono".utf8))
        #expect(model.selectedJob?.previewAppearance == .mono)
        model.stopAllTasks()
    }

    @Test func conversionUsesCapturedAppearanceAndAppearanceChangeClearsOutput() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = try makeIcon("Convert.icon", in: workspace.url)
        let converter = RecordingConverter(previewData: Data("converted".utf8))
        let model = ConversionViewModel(externalToolsPermitted: true, converter: converter,
            previewRenderer: { _, _, _ in Data("preview".utf8) })
        model.tools = try fixtureTools(composer: true)
        model.destination = workspace.url
        model.appearance = .dark
        model.importFiles([icon])
        await waitForPreview(model)

        model.startConversion()
        for _ in 0..<400 {
            if !model.isConverting, model.selectedJob?.output != nil { break }
            await Task.yield()
        }

        #expect(await converter.recordedAppearances() == [.dark])
        #expect(model.selectedJob?.outputAppearance == .dark)
        #expect(model.selectedJob?.status == "Exported and verified")
        #expect(model.revealTarget != nil)

        model.appearance = .mono
        #expect(model.selectedJob?.output == nil)
        #expect(model.selectedJob?.outputAppearance == nil)
        #expect(model.selectedJob?.status == "Ready")
        #expect(model.revealTarget == nil)
        #expect(model.selectedJob?.preview == nil)
        model.stopAllTasks()
    }

    @Test func missingComposerDisablesOnlyDarkAndMono() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = try makeIcon("Tools.icon", in: workspace.url)
        let model = ConversionViewModel(externalToolsPermitted: true,
            previewRenderer: { _, _, _ in Data("preview".utf8) })
        model.tools = try fixtureTools(composer: false)
        model.destination = workspace.url
        model.importFiles([icon])
        #expect(model.canConvert)
        #expect(model.appearanceIssue == nil)

        model.appearance = .dark
        #expect(model.appearanceIssue?.contains("Icon Composer") == true)
        #expect(!model.canConvert)
        model.appearance = .mono
        #expect(model.appearanceIssue?.contains("Icon Composer") == true)
        #expect(!model.canConvert)
        model.appearance = .default
        #expect(model.appearanceIssue == nil)
        #expect(model.canConvert)
        model.stopAllTasks()
    }

    private func waitForRequest(_ gate: PreviewGate, _ appearance: IconAppearance) async -> Bool {
        for _ in 0..<400 {
            if await gate.requested(appearance) { return true }
            await Task.yield()
        }
        return false
    }

    private func waitForPreview(_ model: ConversionViewModel) async {
        for _ in 0..<400 {
            if !model.isPreviewing, model.selectedJob?.preview != nil { return }
            await Task.yield()
        }
    }

    private func makeIcon(_ name: String, in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try Data("{\"groups\":[]}".utf8).write(to: url.appendingPathComponent("icon.json"))
        return url
    }

    private func fixtureTools(composer: Bool) throws -> DeveloperTools {
        var fields = """
        "developerDirectory":"file:///fixture/Xcode/Contents/Developer",
        "xcodebuild":"file:///fixture/xcodebuild","actool":"file:///fixture/actool",
        "clang":"file:///fixture/clang","sdk":"file:///fixture/SDK","sdkVersion":"27.0",
        "iconutil":"file:///usr/bin/iconutil","xcodeVersion":"fixture","operatingSystem":"fixture"
        """
        if composer { fields += ",\"composerTool\":\"file:///fixture/ictool\"" }
        return try JSONDecoder().decode(DeveloperTools.self, from: Data("{\(fields)}".utf8))
    }
}
