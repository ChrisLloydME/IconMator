import AppKit
import IconConversionCore
import Observation
import UniformTypeIdentifiers

struct ConversionJob: Identifiable {
    let id = UUID()
    let input: URL
    var status = "Ready"
    var output: URL?
    var preview: Data?
    var error: String?
    var diagnostics = ""
}

@MainActor @Observable
final class ConversionViewModel {
    var jobs: [ConversionJob] = []
    var selection: UUID?
    var destination: URL?
    var exportPNG = false
    var tools: DeveloperTools?
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
    @ObservationIgnored private let service = IconConversionService()

    init(externalToolsPermitted: Bool? = nil) {
        #if ICONMATOR_APP_SANDBOX_YES
        self.externalToolsPermitted = externalToolsPermitted ?? false
        #else
        self.externalToolsPermitted = externalToolsPermitted ?? true
        #endif
    }

    var selectedJob: ConversionJob? { jobs.first { $0.id == selection } }
    var canConvert: Bool { tools != nil && toolIssue == nil && !isConverting && !isCheckingTools && !jobs.isEmpty && destination != nil }

    func refreshTools() {
        guard !isConverting, !isCheckingTools else { return }
        guard externalToolsPermitted else {
            toolIssue = "This build has App Sandbox enabled. The external Xcode compiler pipeline requires a local build without App Sandbox. The verified command-line converter remains available."
            toolStatus = "External rendering unavailable in this build"
            return
        }
        isCheckingTools = true; toolIssue = nil; tools = nil
        previewTask?.cancel()
        toolTask = Task {
            defer { isCheckingTools = false }
            do {
                let found = try await DeveloperToolLocator().locate()
                try found.requireResearchedEnvironment()
                tools = found
                toolStatus = "macOS \(found.operatingSystem) · \(found.xcodeVersion.components(separatedBy: .newlines).first ?? "Xcode")"
                renderSelectedPreview()
            } catch {
                toolIssue = error.localizedDescription
                toolStatus = "Conversion unavailable"
            }
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !isConverting else { return }
        var errors: [String] = []
        for url in urls {
            let input = url.standardizedFileURL
            guard !jobs.contains(where: { $0.input == input }) else { continue }
            do {
                try IconConversionService.validateInput(input)
                jobs.append(ConversionJob(input: input))
            } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        message = errors.isEmpty ? nil : errors.joined(separator: "\n")
        if selection == nil { selection = jobs.first?.id }
    }

    func selectFiles() {
        let panel = NSOpenPanel()
        panel.title = "Import Icon Composer files"
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true; panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "icon") ?? .package]
        if panel.runModal() == .OK { importFiles(panel.urls) }
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
        jobs.removeAll { $0.id == selection }
        selection = jobs.first?.id
    }

    func renderSelectedPreview() {
        previewTask?.cancel(); previewGeneration = UUID(); isPreviewing = false
        guard !isConverting, let tools, toolIssue == nil, let job = selectedJob, job.preview == nil else { return }
        let id = job.id, generation = previewGeneration
        isPreviewing = true
        previewTask = Task {
            do {
                let data = try await service.preview(input: job.input, tools: tools)
                try Task.checkCancellation()
                if let index = jobs.firstIndex(where: { $0.id == id }) { jobs[index].preview = data; jobs[index].error = nil }
            } catch is CancellationError {
                // Selection changes cancel this preview only.
            } catch {
                if let index = jobs.firstIndex(where: { $0.id == id }) {
                    jobs[index].error = "Preview: \(error.localizedDescription)"
                    jobs[index].diagnostics = (error as? ConversionError)?.diagnostic ?? ""
                }
            }
            if previewGeneration == generation { isPreviewing = false }
        }
    }

    func startConversion() {
        guard canConvert, let tools, let destination else { return }
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
        previewTask?.cancel(); isPreviewing = false; isConverting = true; completed = 0; message = nil
        let savePNG = exportPNG
        conversionTask = Task {
            defer { isConverting = false; currentStage = ""; conversionTask = nil }
            for item in plan {
                if Task.isCancelled { break }
                guard let index = jobs.firstIndex(where: { $0.input == item.input }) else { continue }
                let id = jobs[index].id
                jobs[index].error = nil; jobs[index].output = nil
                do {
                    let result = try await service.convert(input: item.input, destination: item.output, tools: tools,
                        exportPNG: savePNG, overwrite: replace) { stage in
                        await self.updateProgress(id: id, stage: stage)
                    }
                    jobs[index].output = result.icns
                    jobs[index].preview = result.previewPNG
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

    func stopAllTasks() { conversionTask?.cancel(); previewTask?.cancel(); toolTask?.cancel() }
    func cancel() { conversionTask?.cancel() }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
