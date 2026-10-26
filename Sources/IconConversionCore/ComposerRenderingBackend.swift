import CoreGraphics
import Foundation
import ImageIO

/// Renders an explicit Icon Composer generation and appearance, normalizes the
/// complete canvas to sRGB, and presents it through the same public system-icon
/// canvas used by the Default backend. The selected generation is always passed
/// to Apple's renderer; the temporary app bundle is never launched.
public struct ComposerRenderingBackend: IconRenderingBackend {
    private let runner: any ProcessRunning
    public init(runner: any ProcessRunning = ProcessRunner()) { self.runner = runner }

    /// The exact renderer invocation used by the production Composer path.
    /// Kept separate so process-argument tests do not need mocked images.
    public static func rendererArguments(input: URL, output: URL, options: IconRenderOptions) throws -> [String] {
        guard let rendition = options.appearance.composerRendition else {
            throw ConversionError.unsupportedTool("No verified Icon Composer rendition is defined for \(options.appearance.displayName).")
        }
        return [input.path, "--export-image", "--output-file", output.path,
                "--platform", "macOS", "--rendition", rendition.rawValue,
                "--width", "1024", "--height", "1024", "--scale", "1",
                "--design-generation", String(options.generation.rawValue)]
    }

    public func render(input: URL, options: IconRenderOptions, workspace: URL, tools: DeveloperTools) async throws -> RenderedIcon {
        try tools.requireSupportedSDK()
        guard let composer = tools.composerTool else {
            throw ConversionError.missingTool("The Icon Composer renderer was not found in the selected Xcode. \(options.generation.displayName) \(options.appearance.displayName) rendering requires the renderer bundled with the selected Xcode.")
        }
        guard FileManager.default.isExecutableFile(atPath: composer.path) else {
            throw ConversionError.missingTool("The Icon Composer renderer is not executable: \(composer.path)")
        }
        guard let composerInfo = tools.composerInfo else {
            throw ConversionError.missingTool("The Icon Composer renderer version could not be read: \(composer.path). Reinstall or reselect Xcode before exporting \(options.displayName).")
        }
        guard let interface = composerInfo.interface else {
            throw ConversionError.unsupportedTool("The Icon Composer renderer help output could not be inspected: \(composer.path). Explicit \(options.generation.displayName) rendering requires --export-image, --rendition and --design-generation; no fallback is used.")
        }
        guard interface.supportsRequiredArguments else {
            let missing = interface.missingOptions.joined(separator: ", ")
            throw ConversionError.unsupportedTool("The selected Icon Composer renderer does not expose \(missing). \(options.generation.displayName) rendering cannot be requested explicitly; the host generation is not substituted.")
        }
        guard let rendition = options.appearance.composerRendition else {
            throw ConversionError.unsupportedTool("No verified Icon Composer rendition is defined for \(options.appearance.displayName).")
        }

        let fm = FileManager.default
        let snapshot = workspace.appendingPathComponent("AppIcon.icon")
        try fm.copyItem(at: input, to: snapshot)
        let direct = workspace.appendingPathComponent("Composer-\(options.generation.rawValue)-\(options.appearance.rawValue)-1024.png")
        let arguments = try Self.rendererArguments(input: snapshot, output: direct, options: options)
        let render = try await runner.run(executable: composer, arguments: arguments,
            directory: workspace, environment: tools.environment)
        try Task.checkCancellation()

        guard let imageSource = CGImageSourceCreateWithURL(direct as CFURL, nil),
              let directImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ConversionError.invalidImage("The Icon Composer renderer produced no readable image for \(options.displayName).")
        }
        let hasAlpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(directImage.alphaInfo)
        guard directImage.width == 1024, directImage.height == 1024, hasAlpha else {
            throw ConversionError.invalidImage("The Icon Composer renderer returned \(directImage.width)×\(directImage.height); a 1024×1024 RGBA master is required for \(options.displayName).")
        }

        // A single explicit normalization keeps the legacy ICNS presentation from
        // interpreting Display P3 data as untagged sRGB.
        let normalizedURL = workspace.appendingPathComponent("Composer-\(options.generation.rawValue)-\(options.appearance.rawValue)-1024-sRGB.png")
        try ICNSBuilder.write(SystemIconExtractor.normalizedSRGB(directImage, width: 1024, height: 1024), to: normalizedURL)
        let normalized = try RasterImage(url: normalizedURL)
        guard normalized.width == 1024, normalized.height == 1024, normalized.geometry.sourceHasAlpha,
              normalized.geometry.visibleBounds != nil else {
            throw ConversionError.invalidImage("The normalized Composer master is not a genuine 1024×1024 RGBA image.")
        }

        // Package the normalized master into a temporary legacy ICNS. The system
        // applies the macOS icon canvas and shadow to this art during extraction.
        let legacyICNS = try await ICNSBuilder(runner: runner).fromPNG(normalizedURL, workspace: workspace, tool: tools.iconutil)
        let bundle = workspace.appendingPathComponent("Composer-\(UUID().uuidString).app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        let binaries = bundle.appendingPathComponent("Contents/MacOS")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.createDirectory(at: binaries, withIntermediateDirectories: true)
        try fm.copyItem(at: legacyICNS, to: resources.appendingPathComponent("AppIcon.icns"))
        let stub = workspace.appendingPathComponent("main.c")
        try Data("int main(void) { return 0; }\n".utf8).write(to: stub)
        let stubCompilation = try await runner.run(executable: tools.clang,
            arguments: [stub.path, "-isysroot", tools.sdk.path, "-mmacosx-version-min=26.0", "-o", binaries.appendingPathComponent("RenderStub").path],
            directory: workspace, environment: tools.environment)
        let info: [String: String] = [
            "CFBundleIdentifier": "com.lloydME.IconMator.Composer.\(UUID().uuidString)",
            "CFBundleName": "IconMator Composer Render", "CFBundleExecutable": "RenderStub",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL",
            "CFBundleIconFile": "AppIcon", "LSMinimumSystemVersion": "26.0"
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try Task.checkCancellation()

        let iconset = workspace.appendingPathComponent("Rendered.iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: false)
        let extractionDiagnostics = try await SystemIconExtractor.extract(bundle: bundle, to: iconset)
        try ConversionValidator().validateIconset(iconset)
        let master = iconset.appendingPathComponent("icon_512x512@2x.png")
        let masterImage = try RasterImage(url: master)

        var diagnostics = "Rendering: \(options.generation.displayName)\n"
        diagnostics += "Appearance: \(options.appearance.displayName)\n"
        diagnostics += "Rendition: \(rendition.rawValue)\n"
        diagnostics += "Backend: \(RenderCapabilities.composerBackendName)\n"
        diagnostics += "Host: macOS \(tools.operatingSystem); Xcode: \(tools.xcodeVersion.trimmingCharacters(in: .whitespacesAndNewlines)); SDK: macOS \(tools.sdkVersion)\n"
        diagnostics += "Composer: \(composer.path) (\(composerInfo.displayVersion))\n"
        diagnostics += "Composer interface: --export-image, --rendition, --design-generation\n"
        diagnostics += "Generation argument: --design-generation \(options.generation.rawValue)\n"
        diagnostics += "Direct export: \(directImage.width)×\(directImage.height), \(directImage.bitsPerComponent) bits/component, "
        diagnostics += "\(directImage.colorSpace?.name as String? ?? "unspecified color space"), alpha=true, toneMap=\(directImage.shouldToneMap)\n"
        diagnostics += "Normalization: complete canvas to 8-bit sRGB premultiplied RGBA; tone mapping \(directImage.shouldToneMap ? "none" : "automatic")\n"
        diagnostics += "Presentation: temporary legacy ICNS in a fresh application bundle; public NSWorkspace extraction supplies the current host's macOS canvas and shadow\n"
        diagnostics += "Final 1024 canvas: alpha>=1 \(Self.describe(masterImage.geometry.visibleBounds)), alpha>=128 \(Self.describe(masterImage.geometry.solidBounds))\n"
        diagnostics += "Independent ICNS packaging: iconutil decode and exact normalized pixel comparison passed for all ten representations\n"
        if !render.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics += "Renderer output: \(render.output.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }
        diagnostics += stubCompilation.output
        diagnostics += extractionDiagnostics

        return RenderedIcon(iconset: iconset, masterPNG: master,
            diagnostics: diagnostics, options: options,
            rendition: rendition.rawValue,
            backend: RenderCapabilities.composerBackendName,
            composerVersion: composerInfo.displayVersion)
    }

    private static func describe(_ bounds: PixelBounds?) -> String {
        guard let bounds else { return "none" }
        return "x=\(bounds.x) y=\(bounds.y) w=\(bounds.width) h=\(bounds.height)"
    }
}
