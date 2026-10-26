import AppKit
import IconConversionCore
import Observation

struct ConversionJob: Identifiable {
    let id = UUID()
    let input: URL
    var status = "Ready"
    var output: URL?
    var outputAppearance: IconAppearance?
    var preview: Data?
    var previewAppearance: IconAppearance?
    var previewToolIdentity: String?
    var error: String?
    var diagnostics = ""
}

@MainActor @Observable
final class ConversionViewModel {
    var jobs: [ConversionJob] = []
    var selection: UUID? {
        didSet {
            if selection != oldValue { renderSelectedPreview() }
        }
    }
    var destination: URL?
    var exportPNG = false
    var appearance: IconAppearance = .default {
        didSet {
            guard appearance != oldValue, !isConverting else { return }
            invalidatePreviewsAndOutputs()
            renderSelectedPreview()
        }
    }
    var tools: DeveloperTools?
    var appearanceCapabilities: AppearanceCapabilities?
    var toolStatus = "Checking developer tools…"
    var toolIssue: String?
    var message: String?
    var isCheckingTools = false
    var isConverting = false
    var isPreviewing = false
    var completed = 0
    var currentStage = ""
    @ObservationIgnored private var conversionTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var toolTask: Task<Void, Never>?
    @ObservationIgnored private var previewGeneration = UUID()
    @ObservationIgnored private let externalToolsPermitted: Bool
    @ObservationIgnored private let converter: any IconConversionPerforming
    @ObservationIgnored private let previewRenderer: @Sendable (URL, IconAppearance, DeveloperTools) async throws -> Data

    init(externalToolsPermitted: Bool? = nil,
         converter: any IconConversionPerforming = IconConversionService(),
         previewRenderer: @escaping @Sendable (URL, IconAppearance, DeveloperTools) async throws -> Data = { input, appearance, tools in
             try await IconConversionService().preview(input: input, appearance: appearance, tools: tools)
         }) {
        self.converter = converter
        self.previewRenderer = previewRenderer
        #if ICONMATOR_APP_SANDBOX_YES
        self.externalToolsPermitted = externalToolsPermitted ?? false
        #else
        self.externalToolsPermitted = externalToolsPermitted ?? true
        #endif
    }

    var selectedJob: ConversionJob? { jobs.first { $0.id == selection } }
    var canConvert: Bool {
        tools != nil && toolIssue == nil && !isConverting && !isCheckingTools &&
        !jobs.isEmpty && destination != nil && appearanceIssue == nil
    }
    var revealTarget: URL? {
        guard let job = selectedJob, job.outputAppearance == appearance else { return nil }
        return job.output
    }
    var appearanceIssue: String? {
        guard appearance != .default else { return nil }
        if let capability = appearanceCapabilities?.capability(for: appearance) {
            return capability.isSupported ? nil : (capability.reason ?? "This appearance is unavailable.")
        }
        guard tools != nil else { return "Developer tools are not ready." }
        guard tools?.composerTool != nil else {
            return "Dark and Mono require the Icon Composer renderer bundled with the selected Xcode."
        }
        return nil
    }

    func refreshTools() {
        guard !isConverting, !isCheckingTools else { return }
        guard externalToolsPermitted else {
            toolIssue = "This build has App Sandbox enabled. The external Xcode compiler pipeline requires a local build without App Sandbox. The verified command-line converter remains available."
            toolStatus = "External rendering unavailable in this build"
            return
        }
        isCheckingTools = true; toolIssue = nil; tools = nil; appearanceCapabilities = nil
        invalidatePreviewsAndOutputs()
        toolTask = Task {
            defer { isCheckingTools = false }
            do {
                let found = try await DeveloperToolLocator().locate()
                try Task.checkCancellation()
                try found.requireResearchedEnvironment()
                let capabilities = await AppearanceCapabilities.probe(tools: found)
                try Task.checkCancellation()
                tools = found
                appearanceCapabilities = capabilities
                var status = "macOS \(found.operatingSystem) · \(found.xcodeVersion.components(separatedBy: .newlines).first ?? "Xcode")"
                if let composer = capabilities.composerTool {
                    status += " · Icon Composer \(composer.displayVersion)"
                } else if found.composerTool != nil {
                    status += " · Icon Composer version unreadable"
                }
                toolStatus = status
                renderSelectedPreview()
            } catch is CancellationError {
                // A newer refresh or window teardown owns the tool state now.
            } catch {
                toolIssue = error.localizedDescription
                toolStatus = "Conversion unavailable"
            }
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !isConverting else { return }
        var errors: [String] = []
        var firstNew: UUID?
        var firstExisting: UUID?
        for url in urls {
            let input = url.standardizedFileURL
            if let existing = jobs.first(where: { $0.input.path == input.path }) {
                if firstExisting == nil { firstExisting = existing.id }
                continue
            }
            do {
                try IconConversionService.validateInput(input)
                let job = ConversionJob(input: input)
                jobs.append(job)
                if firstNew == nil { firstNew = job.id }
            } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        message = errors.isEmpty ? nil : errors.joined(separator: "\n")
        selection = firstNew ?? firstExisting ?? selection ?? jobs.first?.id
    }

    func selectFiles() {
        let panel = NSOpenPanel()
        let delegate = IconImportPanelDelegate()
        IconImportPanelDelegate.configure(panel)
        panel.delegate = delegate
        let response = withExtendedLifetime(delegate) { panel.runModal() }
        if response == .OK { importFiles(panel.urls) }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose export folder"; panel.prompt = "Choose"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { destination = panel.url }
    }

    func removeSelected() {
        guard !isConverting else { return }
        previewTask?.cancel()
        previewGeneration = UUID()
        isPreviewing = false
        jobs.removeAll { $0.id == selection }
        selection = jobs.first?.id
    }

    func renderSelectedPreview() {
        previewTask?.cancel(); previewGeneration = UUID(); isPreviewing = false
        guard !isConverting, let tools, toolIssue == nil, let job = selectedJob else { return }
        if let issue = appearanceIssue {
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[index].preview = nil
                jobs[index].previewAppearance = nil
                jobs[index].previewToolIdentity = nil
                jobs[index].error = "Preview: \(issue)"
            }
            return
        }
        let identity = tools.identity
        if job.preview != nil, job.previewAppearance == appearance, job.previewToolIdentity == identity { return }
        let id = job.id, generation = previewGeneration, capturedAppearance = appearance
        isPreviewing = true
        previewTask = Task {
            do {
                let data = try await previewRenderer(job.input, capturedAppearance, tools)
                try Task.checkCancellation()
                guard previewGeneration == generation,
                      self.appearance == capturedAppearance,
                      self.tools?.identity == identity,
                      let index = jobs.firstIndex(where: { $0.id == id }) else { return }
                jobs[index].preview = data
                jobs[index].previewAppearance = capturedAppearance
                jobs[index].previewToolIdentity = identity
                jobs[index].error = nil
            } catch is CancellationError {
                // A newer selection, appearance, or tool refresh owns the preview now.
            } catch {
                guard !Task.isCancelled, previewGeneration == generation,
                      self.appearance == capturedAppearance else { return }
                if let index = jobs.firstIndex(where: { $0.id == id }) {
                    jobs[index].preview = nil
                    jobs[index].previewAppearance = nil
                    jobs[index].previewToolIdentity = nil
                    jobs[index].error = "Preview: \(error.localizedDescription)"
                    jobs[index].diagnostics = (error as? ConversionError)?.diagnostic ?? ""
                }
            }
            if previewGeneration == generation { isPreviewing = false }
        }
    }

    func startConversion() {
        guard canConvert, let tools, let destination else { return }
        let batchAppearance = appearance
        let plan = BatchPlanner.plan(inputs: jobs.map(\.input), folder: destination)
        let existing = plan.flatMap { item in
            [item.output] + (exportPNG ? [item.output.deletingPathExtension().appendingPathExtension("png")] : [])
        }.filter { FileManager.default.fileExists(atPath: $0.path) }
        var replace = false
        if !existing.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Replace \(existing.count) existing export\(existing.count == 1 ? "" : "s")?"
            alert.informativeText = existing.map(\.lastPathComponent).joined(separator: "\n")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Replace")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            replace = true
        }
        previewTask?.cancel(); previewGeneration = UUID(); isPreviewing = false
        isConverting = true; completed = 0; message = nil
        let savePNG = exportPNG
        conversionTask = Task {
            defer { isConverting = false; currentStage = ""; conversionTask = nil }
            for item in plan {
                if Task.isCancelled || self.appearance != batchAppearance { break }
                guard let index = jobs.firstIndex(where: { $0.input == item.input }) else { continue }
                let id = jobs[index].id
                jobs[index].error = nil; jobs[index].output = nil; jobs[index].outputAppearance = nil
                do {
                    let result = try await converter.convert(input: item.input, destination: item.output, tools: tools,
                        appearance: batchAppearance, exportPNG: savePNG, overwrite: replace) { stage in
                        await self.updateProgress(id: id, stage: stage)
                    }
                    guard !Task.isCancelled, self.appearance == batchAppearance else { break }
                    jobs[index].output = result.icns
                    jobs[index].outputAppearance = result.appearance
                    jobs[index].preview = result.previewPNG
                    jobs[index].previewAppearance = result.appearance
                    jobs[index].previewToolIdentity = tools.identity
                    jobs[index].diagnostics = result.environment + "\n" + result.diagnostics
                    jobs[index].status = "Exported and verified"
                } catch is CancellationError {
                    jobs[index].status = "Cancelled"; break
                } catch {
                    jobs[index].status = "Failed"; jobs[index].error = error.localizedDescription
                    jobs[index].diagnostics = (error as? ConversionError)?.diagnostic ?? String(describing: error)
                }
                completed += 1
            }
        }
    }

    private func updateProgress(id: UUID, stage: ConversionStage) {
        currentStage = stage.rawValue
        if let index = jobs.firstIndex(where: { $0.id == id }) { jobs[index].status = stage.rawValue }
    }

    /// Clears anything that was rendered for the previous appearance or tool
    /// identity. A late result must not be shown as if it belonged to the new
    /// selection.
    private func invalidatePreviewsAndOutputs() {
        previewTask?.cancel()
        previewGeneration = UUID()
        isPreviewing = false
        for index in jobs.indices {
            jobs[index].preview = nil
            jobs[index].previewAppearance = nil
            jobs[index].previewToolIdentity = nil
            jobs[index].output = nil
            jobs[index].outputAppearance = nil
            jobs[index].diagnostics = ""
            jobs[index].error = nil
            jobs[index].status = "Ready"
        }
    }

    func stopAllTasks() {
        conversionTask?.cancel(); previewTask?.cancel(); toolTask?.cancel()
        previewGeneration = UUID()
    }
    func cancel() { conversionTask?.cancel() }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
