import Foundation

/// Options advertised by the selected Icon Composer renderer's help output.
///
/// Only the three options used by the production path are tracked. Parsing is
/// deliberately narrow and token-based so formatting, wrapping or quotation
/// changes do not turn a supported renderer into an unsupported one.
public struct ComposerInterfaceCapabilities: Codable, Sendable, Equatable {
    public let exportImage: Bool
    public let rendition: Bool
    public let designGeneration: Bool

    public init(exportImage: Bool, rendition: Bool, designGeneration: Bool) {
        self.exportImage = exportImage
        self.rendition = rendition
        self.designGeneration = designGeneration
    }

    public var supportsRequiredArguments: Bool {
        exportImage && rendition && designGeneration
    }

    public var missingOptions: [String] {
        var missing: [String] = []
        if !exportImage { missing.append("--export-image") }
        if !rendition { missing.append("--rendition") }
        if !designGeneration { missing.append("--design-generation") }
        return missing
    }

    var identityFragment: String {
        "export-image:\(exportImage)|rendition:\(rendition)|design-generation:\(designGeneration)"
    }

    /// Finds option tokens without depending on surrounding punctuation or
    /// indentation. The lookarounds prevent matching a longer option name.
    public static func parse(help: String) -> Self {
        func exposes(_ option: String) -> Bool {
            let escaped = NSRegularExpression.escapedPattern(for: option)
            let pattern = "(?<![A-Za-z0-9_-])\(escaped)(?![A-Za-z0-9_-])"
            return help.range(of: pattern, options: .regularExpression) != nil
        }
        return Self(exportImage: exposes("--export-image"),
                    rendition: exposes("--rendition"),
                    designGeneration: exposes("--design-generation"))
    }
}

public struct ComposerToolInfo: Codable, Sendable, Equatable {
    public let path: String
    public let shortVersion: String?
    public let buildVersion: String?
    /// Nil when `--help` could not be read. Individual flags are false when the
    /// option was absent from otherwise readable help output.
    public let interface: ComposerInterfaceCapabilities?

    public init(path: String, shortVersion: String?, buildVersion: String?,
                interface: ComposerInterfaceCapabilities? = nil) {
        self.path = path
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.interface = interface
    }

    public var displayVersion: String {
        switch (shortVersion, buildVersion) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        case let (nil, build?): return "build \(build)"
        case (nil, nil): return "unknown version"
        }
    }

    public var supportsGenerationSelection: Bool {
        interface?.designGeneration == true
    }

    var identityFragment: String {
        "\(shortVersion ?? "unknown")|\(buildVersion ?? "unknown")|\(interface?.identityFragment ?? "help-unreadable")"
    }

    /// Reads `ictool --version` and `ictool --help`. A successful version
    /// invocation with no readable version is treated as unavailable rather than
    /// assumed compatible. Help failure still yields version information but
    /// leaves `interface` nil so generation-dependent requests fail explicitly.
    /// Cancellation is propagated so an obsolete tool check cannot be reported
    /// as a missing tool.
    public static func load(tools: DeveloperTools,
                            runner: any ProcessRunning = ProcessRunner()) async throws -> ComposerToolInfo? {
        guard let tool = tools.composerTool, FileManager.default.isExecutableFile(atPath: tool.path) else { return nil }
        let output: String
        do {
            output = try await runner.run(executable: tool, arguments: ["--version"],
                                          directory: nil, environment: tools.environment).output
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

        let help: String?
        do {
            help = try await runner.run(executable: tool, arguments: ["--help"],
                                        directory: nil, environment: tools.environment).output
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            help = nil
        }
        let interface = help.map(ComposerInterfaceCapabilities.parse(help:))
        return ComposerToolInfo(path: tool.path, shortVersion: short, buildVersion: build,
                                interface: interface)
    }
}

public struct RenderCapability: Codable, Sendable, Equatable {
    public let generation: IconDesignGeneration
    public let appearance: IconAppearance
    public let isSupported: Bool
    public let backend: String
    public let rendition: String?
    public let requiresComposer: Bool
    public let reason: String?
    public let verification: String?

    public init(generation: IconDesignGeneration, appearance: IconAppearance, isSupported: Bool,
                backend: String, rendition: String?, requiresComposer: Bool,
                reason: String?, verification: String?) {
        self.generation = generation
        self.appearance = appearance
        self.isSupported = isSupported
        self.backend = backend
        self.rendition = rendition
        self.requiresComposer = requiresComposer
        self.reason = reason
        self.verification = verification
    }

    public var options: IconRenderOptions {
        IconRenderOptions(generation: generation, appearance: appearance)
    }
}

public struct RenderCapabilities: Codable, Sendable, Equatable {
    public static let compiledBackendName = "Compiled icon assets + system icon presentation"
    public static let composerBackendName = "Icon Composer renderer + system icon presentation"

    /// Identity of the tools and renderer inspection that produced these
    /// capabilities. Cache keys and late-result checks use this value.
    public let toolIdentity: String
    public let composerTool: ComposerToolInfo?
    public let composerIssue: String?
    public let capabilities: [RenderCapability]

    public init(toolIdentity: String, composerTool: ComposerToolInfo?, composerIssue: String?,
                capabilities: [RenderCapability]) {
        self.toolIdentity = toolIdentity
        self.composerTool = composerTool
        self.composerIssue = composerIssue
        self.capabilities = capabilities
    }

    public var composerSupportsGenerationSelection: Bool {
        composerTool?.supportsGenerationSelection == true
    }

    public func capability(for options: IconRenderOptions) -> RenderCapability? {
        capabilities.first { $0.generation == options.generation && $0.appearance == options.appearance }
    }

    /// Describes every generation/appearance combination without rendering a
    /// test image. The real integration matrix exercises actual rendering.
    public static func probe(tools: DeveloperTools) -> Self {
        let composerUnavailable = composerUnavailableReason(tools: tools)
        let values = IconDesignGeneration.allCases.flatMap { generation in
            IconAppearance.allCases.map { appearance -> RenderCapability in
                let options = IconRenderOptions(generation: generation, appearance: appearance)
                let route = IconRenderingRouter.route(for: options, tools: tools)
                switch route {
                case .compiledDefault:
                    return RenderCapability(generation: generation, appearance: appearance,
                        isSupported: true, backend: compiledBackendName,
                        rendition: appearance.composerRendition?.rawValue,
                        requiresComposer: false, reason: nil,
                        verification: "Existing measured Default backend, retained only when the host rendering generation matches macOS 27.")
                case .composer:
                    return RenderCapability(generation: generation, appearance: appearance,
                        isSupported: composerUnavailable == nil,
                        backend: composerBackendName,
                        rendition: appearance.composerRendition?.rawValue,
                        requiresComposer: true,
                        reason: composerUnavailable,
                        verification: composerUnavailable == nil
                            ? "Verified by the real generation and appearance integration matrix."
                            : nil)
                }
            }
        }
        return RenderCapabilities(toolIdentity: tools.identity, composerTool: tools.composerInfo,
                                  composerIssue: tools.composerIssue, capabilities: values)
    }

    private static func composerUnavailableReason(tools: DeveloperTools) -> String? {
        guard let tool = tools.composerTool else {
            return "The Icon Composer renderer was not found in the selected Xcode. macOS 26 rendering and the Dark or Mono appearances require the renderer bundled with the selected Xcode."
        }
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            return "The Icon Composer renderer is not executable: \(tool.path)"
        }
        if let issue = tools.composerIssue {
            return issue
        }
        guard let info = tools.composerInfo else {
            return "The Icon Composer renderer version could not be read: \(tool.path). Reinstall or reselect Xcode before exporting this combination."
        }
        guard let interface = info.interface else {
            return "The Icon Composer renderer help output could not be inspected: \(tool.path). It must expose --export-image, --rendition and --design-generation; no generation fallback is used."
        }
        guard interface.supportsRequiredArguments else {
            let missing = interface.missingOptions.joined(separator: ", ")
            return "The selected Icon Composer renderer does not expose \(missing). Explicit macOS 26 or 27 rendering is unavailable for this combination; the host generation is never substituted."
        }
        return nil
    }
}
