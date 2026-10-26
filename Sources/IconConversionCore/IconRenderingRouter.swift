import Foundation

public enum IconRenderingRoute: String, Codable, Sendable, Equatable {
    case compiledDefault
    case composer
}

/// Routes a complete render request to the backend that can actually satisfy it.
///
/// The compiled-asset Default path is host-dependent and is retained only for an
/// explicit macOS 27 request on a known macOS 27 host. Every other combination
/// uses Icon Composer with the requested `--design-generation`.
public struct IconRenderingRouter: IconRenderingBackend {
    private let compiled: any IconRenderingBackend
    private let composer: any IconRenderingBackend

    public init(compiled: any IconRenderingBackend = CompiledAssetBackend(),
                composer: any IconRenderingBackend = ComposerRenderingBackend()) {
        self.compiled = compiled
        self.composer = composer
    }

    public static func route(for options: IconRenderOptions, tools: DeveloperTools) -> IconRenderingRoute {
        if options.appearance == .default,
           options.generation == .macOS27,
           tools.hostDesignGeneration == .macOS27 {
            return .compiledDefault
        }
        return .composer
    }

    public func render(input: URL, options: IconRenderOptions, workspace: URL, tools: DeveloperTools) async throws -> RenderedIcon {
        switch Self.route(for: options, tools: tools) {
        case .compiledDefault:
            return try await compiled.render(input: input, options: options, workspace: workspace, tools: tools)
        case .composer:
            guard tools.composerTool != nil else {
                throw ConversionError.missingTool("\(options.generation.displayName) \(options.appearance.displayName) rendering requires the Icon Composer renderer bundled with the selected Xcode.")
            }
            return try await composer.render(input: input, options: options, workspace: workspace, tools: tools)
        }
    }
}
