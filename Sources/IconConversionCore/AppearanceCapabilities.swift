import Foundation

public struct ComposerToolInfo: Codable, Sendable, Equatable {
    public let path: String
    public let shortVersion: String?
    public let buildVersion: String?

    public init(path: String, shortVersion: String?, buildVersion: String?) {
        self.path = path
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
    }

    public var displayVersion: String {
        switch (shortVersion, buildVersion) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        case let (nil, build?): return "build \(build)"
        case (nil, nil): return "unknown version"
        }
    }

    /// Reads `ictool --version`. A successful invocation with no readable version
    /// is treated as unavailable rather than assumed compatible. Cancellation is
    /// propagated so an obsolete tool check cannot be reported as a missing tool.
    public static func load(tools: DeveloperTools, runner: any ProcessRunning = ProcessRunner()) async throws -> ComposerToolInfo? {
        guard let tool = tools.composerTool, FileManager.default.isExecutableFile(atPath: tool.path) else { return nil }
        let output: String
        do {
            output = try await runner.run(executable: tool, arguments: ["--version"], directory: nil, environment: tools.environment).output
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let short = object["short-bundle-version"] as? String
        let build = object["bundle-version"] as? String
        guard short != nil || build != nil else { return nil }
        return ComposerToolInfo(path: tool.path, shortVersion: short, buildVersion: build)
    }
}

public struct AppearanceCapability: Codable, Sendable, Equatable {
    public let appearance: IconAppearance
    public let isSupported: Bool
    public let backend: String
    public let rendition: String?
    public let reason: String?
    public let verification: String?

    public init(appearance: IconAppearance, isSupported: Bool, backend: String, rendition: String?,
                reason: String?, verification: String?) {
        self.appearance = appearance
        self.isSupported = isSupported
        self.backend = backend
        self.rendition = rendition
        self.reason = reason
        self.verification = verification
    }
}

public struct AppearanceCapabilities: Codable, Sendable, Equatable {
    public let composerTool: ComposerToolInfo?
    public let appearances: [AppearanceCapability]

    public init(composerTool: ComposerToolInfo?, appearances: [AppearanceCapability]) {
        self.composerTool = composerTool
        self.appearances = appearances
    }

    public func capability(for appearance: IconAppearance) -> AppearanceCapability? {
        appearances.first { $0.appearance == appearance }
    }

    /// Describes what is currently available without rendering a test image.
    /// The actual rendering path is exercised by the real integration suite.
    public static func probe(tools: DeveloperTools, runner: any ProcessRunning = ProcessRunner()) async -> AppearanceCapabilities {
        let info = (try? await ComposerToolInfo.load(tools: tools, runner: runner)) ?? nil
        let unavailableReason: String?
        if tools.composerTool == nil {
            unavailableReason = "The Icon Composer renderer was not found in the selected Xcode. Dark and Mono require the renderer bundled with the selected Xcode."
        } else if !FileManager.default.isExecutableFile(atPath: tools.composerTool!.path) {
            unavailableReason = "The Icon Composer renderer is not executable: \(tools.composerTool!.path)"
        } else if info == nil {
            unavailableReason = "The Icon Composer renderer version could not be read: \(tools.composerTool!.path)."
        } else {
            unavailableReason = nil
        }

        let appearances = IconAppearance.allCases.map { appearance -> AppearanceCapability in
            switch appearance {
            case .default:
                return AppearanceCapability(appearance: appearance, isSupported: true,
                    backend: "Compiled icon assets + system icon presentation",
                    rendition: ComposerRendition.default.rawValue, reason: nil,
                    verification: "Existing Default backend; preserved for measured reference quality.")
            case .dark, .mono:
                guard unavailableReason == nil, let rendition = appearance.composerRendition else {
                    return AppearanceCapability(appearance: appearance, isSupported: false,
                        backend: "Icon Composer renderer + system icon presentation",
                        rendition: appearance.composerRendition?.rawValue,
                        reason: unavailableReason ?? "The requested rendition is not available.",
                        verification: nil)
                }
                return AppearanceCapability(appearance: appearance, isSupported: true,
                    backend: "Icon Composer renderer + system icon presentation",
                    rendition: rendition.rawValue, reason: nil,
                    verification: "Verified by the real appearance integration matrix.")
            }
        }
        return AppearanceCapabilities(composerTool: info, appearances: appearances)
    }
}
