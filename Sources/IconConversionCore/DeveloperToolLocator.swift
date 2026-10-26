import Foundation

public struct DeveloperTools: Codable, Sendable {
    public let developerDirectory: URL
    public let xcodebuild: URL
    public let actool: URL
    public let clang: URL
    public let sdk: URL
    public let sdkVersion: String
    public let iconutil: URL
    public let composerTool: URL?
    /// Version and help-interface inspection for the selected Composer renderer.
    /// Nil when the renderer is absent or its version could not be read.
    public let composerInfo: ComposerToolInfo?
    /// Actionable reason when a Composer executable exists but could not be
    /// inspected. This affects only requests that require Composer.
    public let composerIssue: String?
    public let xcodeVersion: String
    public let operatingSystem: String

    public init(developerDirectory: URL, xcodebuild: URL, actool: URL, clang: URL, sdk: URL,
                sdkVersion: String, iconutil: URL, composerTool: URL?,
                composerInfo: ComposerToolInfo? = nil, composerIssue: String? = nil,
                xcodeVersion: String, operatingSystem: String) {
        self.developerDirectory = developerDirectory
        self.xcodebuild = xcodebuild
        self.actool = actool
        self.clang = clang
        self.sdk = sdk
        self.sdkVersion = sdkVersion
        self.iconutil = iconutil
        self.composerTool = composerTool
        self.composerInfo = composerInfo
        self.composerIssue = composerIssue
        self.xcodeVersion = xcodeVersion
        self.operatingSystem = operatingSystem
    }

    public var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["DEVELOPER_DIR"] = developerDirectory.path
        return environment
    }

    /// Stable identity for preview caching and stale-result checks. It includes
    /// the Composer version and help-interface result because explicit
    /// generation selection depends on that renderer inspection.
    public var identity: String {
        let composerIdentity: String
        if let composerInfo {
            composerIdentity = composerInfo.identityFragment
        } else if let composerIssue {
            composerIdentity = "interface-error:\(composerIssue)"
        } else {
            composerIdentity = "no-composer"
        }
        return "\(developerDirectory.path)|\(xcodeVersion)|\(operatingSystem)|\(sdk.path)|\(sdkVersion)|\(composerTool?.path ?? "no-composer")|\(composerIdentity)"
    }

    /// Only a known macOS 27 host may satisfy an explicit macOS 27 generation
    /// request with the existing host-dependent compiled-asset path. Unknown or
    /// future host versions must use an explicit Composer generation request.
    public var hostMacOSMajorVersion: Int? {
        Int(operatingSystem.prefix { $0.isNumber })
    }

    public var hostDesignGeneration: IconDesignGeneration? {
        hostMacOSMajorVersion.flatMap(IconDesignGeneration.init(rawValue:))
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

    /// SDK-family compatibility policy, independent of exact Xcode and host builds.
    /// Structural output validation does not certify visual fidelity on every environment.
    public func requireSupportedSDK() throws {
        // xcrun normally reports a numeric version even for beta SDKs. Accept
        // explicit prerelease suffixes too, without accepting other SDK families.
        let versionPattern = #"^27(?:\.[0-9]+)*(?:[\s-]*(?:beta|b|rc)(?:[\s.]*[0-9]+)?)?$"#
        guard sdkVersion.range(of: versionPattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            throw ConversionError.unsupportedTool("macOS SDK \(sdkVersion). Select a full Xcode installation whose active macOS SDK is 27.x, including beta releases.")
        }
    }
}

public struct DeveloperToolLocator: Sendable {
    private let runner: any ProcessRunning
    private let environment: [String: String]
    public init(runner: any ProcessRunning = ProcessRunner(), environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.runner = runner; self.environment = environment
    }

    public func locate() async throws -> DeveloperTools {
        let env = environment
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
        let sdkVersion = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--sdk", "macosx", "--show-sdk-version"], directory: nil, environment: pinned).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let xcodebuild = developer.appendingPathComponent("usr/bin/xcodebuild")
        let version = try await runner.run(executable: xcodebuild, arguments: ["-version"], directory: nil, environment: pinned).output
        let osVersion = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/sw_vers"), arguments: ["-productVersion"], directory: nil, environment: pinned).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let osBuild = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/sw_vers"), arguments: ["-buildVersion"], directory: nil, environment: pinned).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let composerRoot = developer.deletingLastPathComponent().appendingPathComponent("Applications/Icon Composer.app/Contents/Executables")
        let composer = ["ictool", "icontool"].map { composerRoot.appendingPathComponent($0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        let base = DeveloperTools(developerDirectory: developer, xcodebuild: xcodebuild, actool: actool, clang: clang, sdk: URL(fileURLWithPath: sdkPath), sdkVersion: sdkVersion,
            iconutil: URL(fileURLWithPath: "/usr/bin/iconutil"), composerTool: composer,
            xcodeVersion: version, operatingSystem: "\(osVersion) (\(osBuild))")
        var composerInfo: ComposerToolInfo?
        var composerIssue: String?
        if let composer {
            composerInfo = try await ComposerToolInfo.load(tools: base, runner: runner)
            if composerInfo == nil {
                composerIssue = "The Icon Composer renderer version could not be read: \(composer.path). Reinstall or reselect Xcode before exporting a combination that requires Composer."
            }
        }
        let tools = DeveloperTools(developerDirectory: developer, xcodebuild: xcodebuild, actool: actool, clang: clang, sdk: URL(fileURLWithPath: sdkPath), sdkVersion: sdkVersion,
            iconutil: URL(fileURLWithPath: "/usr/bin/iconutil"), composerTool: composer,
            composerInfo: composerInfo, composerIssue: composerIssue,
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
