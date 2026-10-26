import Foundation

public struct RenderedIcon: Sendable {
    public let iconset: URL
    public let masterPNG: URL
    public let diagnostics: String
    public let options: IconRenderOptions
    public let rendition: String
    public let backend: String
    public let composerVersion: String?

    public init(iconset: URL, masterPNG: URL, diagnostics: String, options: IconRenderOptions,
                rendition: String, backend: String, composerVersion: String?) {
        self.iconset = iconset
        self.masterPNG = masterPNG
        self.diagnostics = diagnostics
        self.options = options
        self.rendition = rendition
        self.backend = backend
        self.composerVersion = composerVersion
    }

    public var generation: IconDesignGeneration { options.generation }
    public var appearance: IconAppearance { options.appearance }
}

public protocol IconRenderingBackend: Sendable {
    func render(input: URL, options: IconRenderOptions, workspace: URL, tools: DeveloperTools) async throws -> RenderedIcon
}

/// Compiles genuine Apple assets, then asks IconServices for their current Default rendering.
/// The temporary app is never launched. Unique bundle identity avoids stale IconServices cache entries.
/// This host-dependent path only satisfies an explicit macOS 27 request on a known macOS 27 host.
public struct CompiledAssetBackend: IconRenderingBackend {
    private let runner: any ProcessRunning
    public init(runner: any ProcessRunning = ProcessRunner()) { self.runner = runner }

    public func render(input: URL, options: IconRenderOptions, workspace: URL, tools: DeveloperTools) async throws -> RenderedIcon {
        guard options.appearance == .default else {
            throw ConversionError.validation("The compiled-asset backend only renders the Default appearance.")
        }
        guard options.generation == .macOS27, tools.hostDesignGeneration == .macOS27 else {
            throw ConversionError.unsupportedTool("The compiled-asset Default path cannot explicitly satisfy \(options.generation.displayName) rendering on this host. Use the Icon Composer renderer for an explicit generation request.")
        }
        try tools.requireSupportedSDK()
        let fm = FileManager.default
        let snapshot = workspace.appendingPathComponent("AppIcon.icon")
        try fm.copyItem(at: input, to: snapshot)
        let bundle = workspace.appendingPathComponent("Render-\(UUID().uuidString).app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        let binaries = bundle.appendingPathComponent("Contents/MacOS")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.createDirectory(at: binaries, withIntermediateDirectories: true)
        let compilation = try await runner.run(executable: tools.actool, arguments: [snapshot.path,
            "--compile", resources.path, "--platform", "macosx", "--minimum-deployment-target", "26.0",
            "--app-icon", "AppIcon", "--standalone-icon-behavior", "all", "--output-partial-info-plist",
            workspace.appendingPathComponent("partial.plist").path, "--output-format", "human-readable-text"],
            directory: workspace, environment: tools.environment)
        // Compiled output must itself contain a real high-resolution representation before runtime extraction.
        let compiledIcon = resources.appendingPathComponent("AppIcon.icns")
        let decoded = try await ConversionValidator(runner: runner).decodeAndValidate(icns: compiledIcon, workspace: workspace, tool: tools.iconutil)
        _ = decoded
        guard fm.fileExists(atPath: resources.appendingPathComponent("Assets.car").path) else {
            throw ConversionError.validation("Asset compilation produced no Assets.car; system rendering is unavailable.")
        }
        let stub = workspace.appendingPathComponent("main.c")
        try Data("int main(void) { return 0; }\n".utf8).write(to: stub)
        let compilationOfStub = try await runner.run(executable: tools.clang,
            arguments: [stub.path, "-isysroot", tools.sdk.path, "-mmacosx-version-min=26.0", "-o", binaries.appendingPathComponent("RenderStub").path],
            directory: workspace, environment: tools.environment)
        let info: [String: String] = [
            "CFBundleIdentifier": "com.lloydME.IconMator.Render.\(UUID().uuidString)",
            "CFBundleName": "IconMator Render", "CFBundleExecutable": "RenderStub",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL",
            "CFBundleIconFile": "AppIcon", "CFBundleIconName": "AppIcon", "LSMinimumSystemVersion": "26.0"
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
        diagnostics += "Rendition: \(ComposerRendition.default.rawValue)\n"
        diagnostics += "Backend: \(RenderCapabilities.compiledBackendName)\n"
        diagnostics += "Host: macOS \(tools.operatingSystem); Xcode: \(tools.xcodeVersion.trimmingCharacters(in: .whitespacesAndNewlines)); SDK: macOS \(tools.sdkVersion)\n"
        diagnostics += "Generation source: host-dependent compiled assets on a known macOS 27 host; no explicit Composer generation argument is used.\n"
        diagnostics += "Final 1024 canvas: alpha>=1 \(Self.describe(masterImage.geometry.visibleBounds)), alpha>=128 \(Self.describe(masterImage.geometry.solidBounds))\n"
        diagnostics += compilation.output + compilationOfStub.output + extractionDiagnostics
        return RenderedIcon(iconset: iconset, masterPNG: master,
            diagnostics: diagnostics, options: options,
            rendition: ComposerRendition.default.rawValue,
            backend: RenderCapabilities.compiledBackendName, composerVersion: nil)
    }

    private static func describe(_ bounds: PixelBounds?) -> String {
        guard let bounds else { return "none" }
        return "x=\(bounds.x) y=\(bounds.y) w=\(bounds.width) h=\(bounds.height)"
    }
}
