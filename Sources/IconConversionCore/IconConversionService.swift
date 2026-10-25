import Foundation
import Darwin

public enum ConversionStage: String, Sendable {
    case checking = "Checking input and tools"
    case rendering = "Compiling and rendering icon"
    case packaging = "Packaging and verifying ICNS"
    case exporting = "Saving verified output"
}

public struct ConversionResult: Sendable {
    public let icns: URL
    public let png: URL?
    public let environment: String
    public let diagnostics: String
    public let previewPNG: Data
}

public struct IconConversionService: Sendable {
    private let backend: any IconRenderingBackend
    private let runner: any ProcessRunning
    public init(backend: any IconRenderingBackend = CompiledAssetBackend(), runner: any ProcessRunning = ProcessRunner()) {
        self.backend = backend; self.runner = runner
    }

    public static func validateInput(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "icon" else { throw ConversionError.invalidInput("Select a .icon package.") }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw ConversionError.invalidInput("The input must be a readable .icon directory, not a symbolic link.") }
        let json = url.appendingPathComponent("icon.json")
        guard let data = try? Data(contentsOf: json), let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              document["groups"] is [Any] else { throw ConversionError.invalidInput("icon.json is missing or invalid. Open and save the document in Icon Composer.") }
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw ConversionError.invalidInput("Cannot read the package contents.")
        }
        for case let file as URL in files {
            if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw ConversionError.invalidInput("The package contains a symbolic link. Export a self-contained document from Icon Composer.")
            }
        }
    }

    public func convert(input: URL, destination: URL, tools: DeveloperTools, exportPNG: Bool = false,
                        overwrite: Bool = false, progress: @escaping @Sendable (ConversionStage) async -> Void = { _ in }) async throws -> ConversionResult {
        try Task.checkCancellation()
        await progress(.checking)
        try Self.validateInput(input)
        try Self.validateDestinations(destination, png: exportPNG)
        let sourcePath = input.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let outputPath = destination.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent).path
        guard !outputPath.hasPrefix(sourcePath) else { throw ConversionError.validation("Choose an export folder outside the input .icon package.") }
        try tools.validatePinnedTools()
        let current = try await DeveloperToolLocator(runner: runner).locate()
        guard current.developerDirectory == tools.developerDirectory, current.xcodeVersion == tools.xcodeVersion,
              current.operatingSystem == tools.operatingSystem else {
            throw ConversionError.unsupportedTool("The selected Xcode or operating system changed. Recheck developer tools before converting.")
        }
        try tools.requireResearchedEnvironment()
        let outputs = [destination] + (exportPNG ? [destination.deletingPathExtension().appendingPathExtension("png")] : [])
        if !overwrite, let existing = outputs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            throw ConversionError.collision(existing.path)
        }
        let workspace = try TemporaryWorkspace()
        defer { workspace.cleanUp() }
        await progress(.rendering)
        let rendered = try await backend.render(input: input, workspace: workspace.url, tools: tools)
        try Task.checkCancellation()
        await progress(.packaging)
        let icns = try await ICNSBuilder(runner: runner).package(iconset: rendered.iconset, workspace: workspace.url, tool: tools.iconutil)
        try Task.checkCancellation()
        await progress(.exporting)
        let previewPNG = try Data(contentsOf: rendered.masterPNG)
        try OutputPublisher.publish(files: [(icns, destination)] + (exportPNG ? [(rendered.masterPNG, outputs[1])] : []), overwrite: overwrite)
        return ConversionResult(icns: destination, png: exportPNG ? outputs[1] : nil,
            environment: "macOS \(tools.operatingSystem); \(tools.xcodeVersion.trimmingCharacters(in: .whitespacesAndNewlines)); Default (current system renderer)",
            diagnostics: rendered.diagnostics, previewPNG: previewPNG)
    }

    public func preview(input: URL, tools: DeveloperTools) async throws -> Data {
        try Task.checkCancellation()
        try Self.validateInput(input)
        try tools.validatePinnedTools()
        let current = try await DeveloperToolLocator(runner: runner).locate()
        guard current.developerDirectory == tools.developerDirectory, current.xcodeVersion == tools.xcodeVersion,
              current.operatingSystem == tools.operatingSystem else {
            throw ConversionError.unsupportedTool("The selected developer tools changed. Recheck developer tools.")
        }
        try tools.requireResearchedEnvironment()
        let workspace = try TemporaryWorkspace()
        defer { workspace.cleanUp() }
        let rendered = try await backend.render(input: input, workspace: workspace.url, tools: tools)
        try Task.checkCancellation()
        return try Data(contentsOf: rendered.masterPNG)
    }

    /// Development/reference path: package an already-rendered PNG without adding margins or changing the master.
    public func packagePNG(input: URL, destination: URL, overwrite: Bool = false) async throws -> URL {
        try Self.validateDestinations(destination, png: false)
        let workspace = try TemporaryWorkspace()
        defer { workspace.cleanUp() }
        let icns = try await ICNSBuilder(runner: runner).fromPNG(input, workspace: workspace.url, tool: URL(fileURLWithPath: "/usr/bin/iconutil"))
        try Task.checkCancellation()
        try OutputPublisher.publish(files: [(icns, destination)], overwrite: overwrite)
        return destination
    }

    private static func validateDestinations(_ destination: URL, png: Bool) throws {
        guard destination.pathExtension.lowercased() == "icns" else { throw ConversionError.validation("Choose an .icns destination filename.") }
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw ConversionError.validation("The export folder is not writable. Choose a folder you can write to.") }
    }
}

public final class TemporaryWorkspace: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private var shouldCleanUp = true
    public init(parent: URL = FileManager.default.temporaryDirectory) throws {
        url = parent.appendingPathComponent("IconMator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    public func preserveForRecovery() { lock.withLock { shouldCleanUp = false } }
    public func cleanUp() {
        lock.withLock { if shouldCleanUp { try? FileManager.default.removeItem(at: url) } }
    }
    deinit { cleanUp() }
}

/// Stage on the destination volume, validate before publishing, and refuse collisions atomically.
/// Multiple outputs are rolled back on handled failure; a process crash may occur between separate file renames.
public enum OutputPublisher {
    public static func publish(files: [(URL, URL)], overwrite: Bool) throws {
        guard let first = files.first else { return }
        let parent = first.1.deletingLastPathComponent()
        guard files.allSatisfy({ $0.1.deletingLastPathComponent() == parent }), Set(files.map { $0.1.path }).count == files.count else {
            throw ConversionError.validation("Outputs must have distinct filenames in the same export folder.")
        }
        let stage = try TemporaryWorkspace(parent: parent)
        defer { stage.cleanUp() }
        var prepared: [(source: URL, destination: URL, backup: URL?)] = []
        for (index, file) in files.enumerated() {
            let existing = FileManager.default.fileExists(atPath: file.1.path)
            if existing && !overwrite { throw ConversionError.collision(file.1.path) }
            if existing {
                let values = try file.1.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ConversionError.validation("Cannot replace a directory or symbolic link: \(file.1.lastPathComponent)") }
            }
            let source = stage.url.appendingPathComponent("new-\(index)")
            try FileManager.default.copyItem(at: file.0, to: source)
            let backup = existing ? stage.url.appendingPathComponent("backup-\(index)") : nil
            if let backup { try FileManager.default.copyItem(at: file.1, to: backup) }
            prepared.append((source, file.1, backup))
        }
        var published: [(source: URL, destination: URL, backup: URL?)] = []
        do {
            for file in prepared {
                let code = file.source.withUnsafeFileSystemRepresentation { source in
                    file.destination.withUnsafeFileSystemRepresentation { destination in
                        overwrite ? rename(source!, destination!) : link(source!, destination!)
                    }
                }
                guard code == 0 else {
                    if errno == EEXIST { throw ConversionError.collision(file.destination.path) }
                    throw ConversionError.validation("Cannot save \(file.destination.lastPathComponent): \(String(cString: strerror(errno))). Check folder permissions and free space.")
                }
                published.append(file)
            }
        } catch {
            var recoveryRequired = false
            for file in published.reversed() {
                if let backup = file.backup {
                    let result = backup.withUnsafeFileSystemRepresentation { source in
                        file.destination.withUnsafeFileSystemRepresentation { destination in rename(source!, destination!) }
                    }
                    if result != 0 { recoveryRequired = true }
                } else { try? FileManager.default.removeItem(at: file.destination) }
            }
            if recoveryRequired {
                stage.preserveForRecovery()
                throw ConversionError.validation("Export failed and an original could not be restored. Recovery backups were preserved at \(stage.url.path).")
            }
            throw error
        }
    }
}
