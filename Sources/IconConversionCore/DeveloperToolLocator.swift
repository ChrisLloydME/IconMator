import Foundation

public struct DeveloperTools: Codable, Sendable {
    public let developerDirectory: URL
    public let xcodebuild: URL
    public let actool: URL
    public let clang: URL
    public let sdk: URL
    public let iconutil: URL
    public let composerTool: URL?
    public let xcodeVersion: String
    public let operatingSystem: String

    public var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["DEVELOPER_DIR"] = developerDirectory.path
        return environment
    }

    public func validatePinnedTools() throws {
        for url in [developerDirectory, xcodebuild, actool, clang, sdk, iconutil] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ConversionError.missingTool("Previously selected tool disappeared: \(url.path)")
            }
        }
        for url in [xcodebuild, actool, clang, iconutil] where !FileManager.default.isExecutableFile(atPath: url.path) {
            throw ConversionError.missingTool(url.path)
        }
    }

    /// Narrow release scope: this is the only combination exercised against the supplied Finder reference.
    public func requireResearchedEnvironment() throws {
        guard xcodeVersion.contains("Xcode 27.1\n"), xcodeVersion.contains("27A9275"),
              operatingSystem == "27.0.1 (26A434)" else {
            throw ConversionError.unsupportedTool("macOS \(operatingSystem), \(xcodeVersion.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

public struct DeveloperToolLocator: Sendable {
    private let runner: any ProcessRunning
    public init(runner: any ProcessRunning = ProcessRunner()) { self.runner = runner }

    public func locate() async throws -> DeveloperTools {
        let env = ProcessInfo.processInfo.environment
        let selection: String
        if let override = env["DEVELOPER_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            selection = url.pathExtension == "app" ? url.appendingPathComponent("Contents/Developer").path : url.path
        } else {
            selection = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/xcode-select"), arguments: ["-p"], directory: nil, environment: env).output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let developer = URL(fileURLWithPath: selection).standardizedFileURL
        guard FileManager.default.fileExists(atPath: developer.appendingPathComponent("usr/bin/xcodebuild").path) else {
            throw ConversionError.missingTool("\(selection) is not a full Xcode developer directory")
        }
        var pinned = env; pinned["DEVELOPER_DIR"] = developer.path
        let actool = try await resolve("actool", environment: pinned)
        let clang = try await resolve("clang", environment: pinned)
        let sdkPath = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--sdk", "macosx", "--show-sdk-path"], directory: nil, environment: pinned).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let xcodebuild = developer.appendingPathComponent("usr/bin/xcodebuild")
        let version = try await runner.run(executable: xcodebuild, arguments: ["-version"], directory: nil, environment: pinned).output
        let osVersion = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/sw_vers"), arguments: ["-productVersion"], directory: nil, environment: pinned).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let osBuild = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/sw_vers"), arguments: ["-buildVersion"], directory: nil, environment: pinned).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let composerRoot = developer.deletingLastPathComponent().appendingPathComponent("Applications/Icon Composer.app/Contents/Executables")
        let composer = ["ictool", "icontool"].map { composerRoot.appendingPathComponent($0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        let tools = DeveloperTools(developerDirectory: developer, xcodebuild: xcodebuild, actool: actool, clang: clang, sdk: URL(fileURLWithPath: sdkPath),
            iconutil: URL(fileURLWithPath: "/usr/bin/iconutil"), composerTool: composer,
            xcodeVersion: version, operatingSystem: "\(osVersion) (\(osBuild))")
        try tools.validatePinnedTools()
        return tools
    }

    private func resolve(_ name: String, environment: [String: String]) async throws -> URL {
        let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--find", name], directory: nil, environment: environment)
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { throw ConversionError.missingTool(name) }
        return URL(fileURLWithPath: path)
    }
}
