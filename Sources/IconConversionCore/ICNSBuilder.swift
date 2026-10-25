import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct IconRepresentation: Sendable {
    public let name: String
    public let pixels: Int
    public let chunk: String
    public static let standard: [Self] = [
        .init(name: "icon_16x16.png", pixels: 16, chunk: "ic04"), .init(name: "icon_16x16@2x.png", pixels: 32, chunk: "ic11"),
        .init(name: "icon_32x32.png", pixels: 32, chunk: "ic05"), .init(name: "icon_32x32@2x.png", pixels: 64, chunk: "ic12"),
        .init(name: "icon_128x128.png", pixels: 128, chunk: "ic07"), .init(name: "icon_128x128@2x.png", pixels: 256, chunk: "ic13"),
        .init(name: "icon_256x256.png", pixels: 256, chunk: "ic08"), .init(name: "icon_256x256@2x.png", pixels: 512, chunk: "ic14"),
        .init(name: "icon_512x512.png", pixels: 512, chunk: "ic09"), .init(name: "icon_512x512@2x.png", pixels: 1024, chunk: "ic10")
    ]
}

public struct ConversionValidator: Sendable {
    private let runner: any ProcessRunning
    public init(runner: any ProcessRunning = ProcessRunner()) { self.runner = runner }

    public func decodeAndValidate(icns: URL, workspace: URL, tool: URL) async throws -> URL {
        let decoded = workspace.appendingPathComponent("decoded-\(UUID().uuidString).iconset")
        _ = try await runner.run(executable: tool, arguments: ["-c", "iconset", icns.path, "-o", decoded.path], directory: nil, environment: nil)
        try validateIconset(decoded)
        return decoded
    }

    public func validateIconset(_ directory: URL) throws {
        for representation in IconRepresentation.standard {
            let raster = try RasterImage(url: directory.appendingPathComponent(representation.name))
            guard raster.width == representation.pixels, raster.height == representation.pixels else {
                throw ConversionError.validation("\(representation.name) has incorrect dimensions.")
            }
            guard raster.geometry.sourceHasAlpha else { throw ConversionError.validation("\(representation.name) has no alpha channel.") }
            guard raster.geometry.visibleBounds != nil else { throw ConversionError.validation("\(representation.name) is entirely transparent.") }
        }
    }
}

public struct ICNSBuilder: Sendable {
    private let runner: any ProcessRunning
    public init(runner: any ProcessRunning = ProcessRunner()) { self.runner = runner }

    /// The 1024 master is copied verbatim; smaller representations are independently downsampled from it.
    public func fromPNG(_ master: URL, workspace: URL, tool: URL) async throws -> URL {
        let image = try RasterImage(url: master)
        guard image.width == 1024, image.height == 1024, image.geometry.sourceHasAlpha else {
            throw ConversionError.validation("A genuine 1024×1024 RGBA master is required; no upscaling is performed.")
        }
        let iconset = workspace.appendingPathComponent("Output.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: false)
        for representation in IconRepresentation.standard {
            try Task.checkCancellation()
            let output = iconset.appendingPathComponent(representation.name)
            if representation.pixels == 1024 { try FileManager.default.copyItem(at: master, to: output) }
            else { try Self.downsample(master, pixels: representation.pixels, output: output) }
        }
        return try await package(iconset: iconset, workspace: workspace, tool: tool)
    }

    public func package(iconset: URL, workspace: URL, tool: URL) async throws -> URL {
        let output = workspace.appendingPathComponent("Output.icns")
        try ConversionValidator().validateIconset(iconset)
        try IconFamilyEncoder.encode(iconset: iconset).write(to: output, options: .atomic)
        let decoded = try await ConversionValidator(runner: runner).decodeAndValidate(icns: output, workspace: workspace, tool: tool)
        // A packaging success must also preserve every normalized pixel, including alpha and the full canvas.
        for rep in IconRepresentation.standard {
            let a = try RasterImage(url: iconset.appendingPathComponent(rep.name))
            let b = try RasterImage(url: decoded.appendingPathComponent(rep.name))
            if a.pixels != b.pixels {
                let maximum = zip(a.pixels, b.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
                let alphaMaximum = stride(from: 3, to: a.pixels.count, by: 4).map { abs(Int(a.pixels[$0]) - Int(b.pixels[$0])) }.max() ?? 0
                throw ConversionError.validation("ICNS round trip changed \(rep.name): maximum channel delta \(maximum), alpha delta \(alphaMaximum).")
            }
        }
        return output
    }

    private static func downsample(_ url: URL, pixels: Int, output: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw ConversionError.invalidImage("Cannot create downsampling context.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let rendered = context.makeImage() else { throw ConversionError.invalidImage("Downsampling failed.") }
        try write(rendered, to: output)
    }

    static func write(_ image: CGImage, to output: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ConversionError.invalidImage("Cannot create PNG output.")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ConversionError.invalidImage("Cannot write PNG output.") }
    }
}
