import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

public struct RenderedIcon: Sendable {
    public let iconset: URL
    public let masterPNG: URL
    public let diagnostics: String
}

public protocol IconRenderingBackend: Sendable {
    func render(input: URL, workspace: URL, tools: DeveloperTools) async throws -> RenderedIcon
}

/// Compiles genuine Apple assets, then asks IconServices for their current Default rendering.
/// The temporary app is never launched. Unique bundle identity avoids stale IconServices cache entries.
public struct CompiledAssetBackend: IconRenderingBackend {
    private let runner: any ProcessRunning
    public init(runner: any ProcessRunning = ProcessRunner()) { self.runner = runner }

    public func render(input: URL, workspace: URL, tools: DeveloperTools) async throws -> RenderedIcon {
        try tools.requireResearchedEnvironment()
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
        let extractionDiagnostics = try await Self.extract(bundle: bundle, to: iconset)
        try ConversionValidator().validateIconset(iconset)
        return RenderedIcon(iconset: iconset, masterPNG: iconset.appendingPathComponent("icon_512x512@2x.png"),
            diagnostics: compilation.output + compilationOfStub.output + extractionDiagnostics)
    }

    @MainActor private static func extract(bundle: URL, to iconset: URL) throws -> String {
        var diagnostics = ""
        var extractionError: Error?
        guard let appearance = NSAppearance(named: .aqua) else { throw ConversionError.validation("Default appearance is unavailable.") }
        appearance.performAsCurrentDrawingAppearance {
            do {
                let icon = NSWorkspace.shared.icon(forFile: bundle.path)
                var rendered: [Int: URL] = [:]
                for rep in IconRepresentation.standard.sorted(by: { $0.pixels > $1.pixels }) {
                    try Task.checkCancellation()
                    let output = iconset.appendingPathComponent(rep.name)
                    if let duplicate = rendered[rep.pixels] {
                        try FileManager.default.copyItem(at: duplicate, to: output)
                        continue
                    }
                    var rect = CGRect(x: 0, y: 0, width: rep.pixels, height: rep.pixels)
                    guard let source = icon.cgImage(forProposedRect: &rect, context: nil, hints: [.interpolation: NSImageInterpolation.high]),
                          source.width >= rep.pixels, source.height >= rep.pixels,
                          source.width == source.height else {
                        throw ConversionError.validation("System renderer returned no genuine \(rep.pixels)×\(rep.pixels) image. No upscaling is allowed.")
                    }
                    guard let context = CGContext(data: nil, width: rep.pixels, height: rep.pixels, bitsPerComponent: 8,
                        bytesPerRow: rep.pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                        throw ConversionError.invalidImage("Cannot allocate rendering context.")
                    }
                    diagnostics += "System request \(rep.pixels)px: source \(source.width)×\(source.height), \(source.bitsPerComponent) bits/component\n"
                    context.interpolationQuality = .high
                    let target = CGRect(x: 0, y: 0, width: rep.pixels, height: rep.pixels)
                    if source.shouldToneMap {
                        guard context.draw(source, in: target, by: .none, options: nil) else { throw ConversionError.invalidImage("Cannot export extended-range system icon.") }
                    } else { context.draw(source, in: target) }
                    guard let result = context.makeImage() else { throw ConversionError.invalidImage("System icon export failed.") }
                    if rep.pixels == 1024 {
                        let generic = NSWorkspace.shared.icon(for: .applicationBundle)
                        var genericRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
                        guard let genericSource = generic.cgImage(forProposedRect: &genericRect, context: nil, hints: nil),
                              let genericContext = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                            throw ConversionError.validation("Cannot validate the system icon against its generic fallback.")
                        }
                        if genericSource.shouldToneMap { _ = genericContext.draw(genericSource, in: genericRect, by: .none, options: nil) }
                        else { genericContext.draw(genericSource, in: genericRect) }
                        if let genericImage = genericContext.makeImage(),
                           let genericData = genericImage.dataProvider?.data, let resultData = result.dataProvider?.data,
                           genericData as Data == resultData as Data {
                            throw ConversionError.validation("IconServices returned a generic application icon instead of the compiled artwork. No fallback was exported.")
                        }
                    }
                    try ICNSBuilder.write(result, to: output)
                    rendered[rep.pixels] = output
                }
            } catch { extractionError = error }
        }
        if let extractionError { throw extractionError }
        return diagnostics
    }
}
