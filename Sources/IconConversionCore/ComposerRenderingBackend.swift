import CoreGraphics
import Foundation
import ImageIO

/// Renders a verified Icon Composer appearance, normalizes the complete canvas
/// to sRGB, and presents it through the same public system-icon canvas used by
/// the Default backend. The appearance-specific artwork comes from Apple's
/// renderer; the temporary app bundle is never launched.
public struct ComposerRenderingBackend: IconRenderingBackend {
    private let runner: any ProcessRunning
    public init(runner: any ProcessRunning = ProcessRunner()) { self.runner = runner }

    public func render(input: URL, appearance: IconAppearance, workspace: URL, tools: DeveloperTools) async throws -> RenderedIcon {
        guard appearance != .default else {
            throw ConversionError.validation("The Composer backend is not used for the Default appearance.")
        }
        try tools.requireSupportedSDK()
        guard let composer = tools.composerTool else {
            throw ConversionError.missingTool("The Icon Composer renderer was not found in the selected Xcode. Dark and Mono require the renderer bundled with the selected Xcode.")
        }
        guard FileManager.default.isExecutableFile(atPath: composer.path) else {
            throw ConversionError.missingTool("The Icon Composer renderer is not executable: \(composer.path)")
        }
        guard let composerInfo = try? await ComposerToolInfo.load(tools: tools, runner: runner) else {
            try Task.checkCancellation()
            throw ConversionError.missingTool("The Icon Composer renderer version could not be read: \(composer.path). Reinstall or reselect Xcode before exporting Dark or Mono.")
        }
        guard let rendition = appearance.composerRendition else {
            throw ConversionError.unsupportedTool("No verified Icon Composer rendition is defined for \(appearance.displayName).")
        }

        let fm = FileManager.default
        let snapshot = workspace.appendingPathComponent("AppIcon.icon")
        try fm.copyItem(at: input, to: snapshot)
        let direct = workspace.appendingPathComponent("Composer-\(appearance.rawValue)-1024.png")
        let render = try await runner.run(executable: composer, arguments: [
            snapshot.path, "--export-image", "--output-file", direct.path,
            "--platform", "macOS", "--rendition", rendition.rawValue,
            "--width", "1024", "--height", "1024", "--scale", "1",
            "--design-generation", "27"
        ], directory: workspace, environment: tools.environment)
        try Task.checkCancellation()

        guard let imageSource = CGImageSourceCreateWithURL(direct as CFURL, nil),
              let directImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ConversionError.invalidImage("The Icon Composer renderer produced no readable image.")
        }
        let hasAlpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(directImage.alphaInfo)
        guard directImage.width == 1024, directImage.height == 1024, hasAlpha else {
            throw ConversionError.invalidImage("The Icon Composer renderer returned \(directImage.width)×\(directImage.height); a 1024×1024 RGBA master is required.")
        }

        // A single explicit normalization keeps the legacy ICNS presentation from
        // interpreting Display P3 data as untagged sRGB.
        let normalizedURL = workspace.appendingPathComponent("Composer-\(appearance.rawValue)-1024-sRGB.png")
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

        var diagnostics = "Appearance: \(appearance.displayName)\n"
        diagnostics += "Rendition: \(rendition.rawValue)\n"
        diagnostics += "Backend: Icon Composer renderer + system icon presentation\n"
        diagnostics += "Composer: \(composer.path) (\(composerInfo.displayVersion))\n"
        diagnostics += "Direct export: \(directImage.width)×\(directImage.height), \(directImage.bitsPerComponent) bits/component, "
        diagnostics += "\(directImage.colorSpace?.name as String? ?? "unspecified color space"), alpha=true, toneMap=\(directImage.shouldToneMap)\n"
        diagnostics += "Normalization: complete canvas to 8-bit sRGB premultiplied RGBA; tone mapping \(directImage.shouldToneMap ? "none" : "automatic")\n"
        diagnostics += "Presentation: temporary legacy ICNS in a fresh application bundle; public NSWorkspace extraction supplies the macOS canvas and shadow\n"
        diagnostics += "Final 1024 canvas: alpha>=1 \(Self.describe(masterImage.geometry.visibleBounds)), alpha>=128 \(Self.describe(masterImage.geometry.solidBounds))\n"
        diagnostics += "Independent ICNS packaging: iconutil decode and exact normalized pixel comparison passed for all ten representations\n"
        if !render.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics += "Renderer output: \(render.output.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }
        diagnostics += stubCompilation.output
        diagnostics += extractionDiagnostics

        return RenderedIcon(iconset: iconset, masterPNG: master, diagnostics: diagnostics,
            appearance: appearance, rendition: rendition.rawValue,
            backend: "Icon Composer renderer + system icon presentation")
    }

    private static func describe(_ bounds: PixelBounds?) -> String {
        guard let bounds else { return "none" }
        return "x=\(bounds.x) y=\(bounds.y) w=\(bounds.width) h=\(bounds.height)"
    }
}
