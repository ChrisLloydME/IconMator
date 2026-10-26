import Foundation

/// Routes the requested appearance to the backend that has been verified for it.
/// Default deliberately remains on the measured compiled-asset backend.
public struct IconRenderingRouter: IconRenderingBackend {
    private let compiled: any IconRenderingBackend
    private let composer: any IconRenderingBackend

    public init(compiled: any IconRenderingBackend = CompiledAssetBackend(),
                composer: any IconRenderingBackend = ComposerRenderingBackend()) {
        self.compiled = compiled
        self.composer = composer
    }

    public func render(input: URL, appearance: IconAppearance, workspace: URL, tools: DeveloperTools) async throws -> RenderedIcon {
        switch appearance {
        case .default:
            return try await compiled.render(input: input, appearance: appearance, workspace: workspace, tools: tools)
        case .dark, .mono:
            guard tools.composerTool != nil else {
                throw ConversionError.missingTool("The Icon Composer renderer was not found in the selected Xcode. Dark and Mono require the renderer bundled with the selected Xcode.")
            }
            return try await composer.render(input: input, appearance: appearance, workspace: workspace, tools: tools)
        }
    }
}
