import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PixelBounds: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}

public struct ImageGeometry: Codable, Sendable {
    public let width: Int
    public let height: Int
    public let sourceBitsPerComponent: Int
    public let sourceColorSpace: String
    public let sourceHasAlpha: Bool
    public let visibleBounds: PixelBounds?
    public let solidBounds: PixelBounds?
    public let transparentPixels: Int
    public let opaquePixels: Int
}

/// A development comparison format: 8-bit sRGB, premultiplied RGBA.
/// Originals are never rewritten. Metrics include the entire canvas.
public struct RasterImage: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]
    public let geometry: ImageGeometry

    public init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConversionError.invalidImage(url.lastPathComponent)
        }
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        guard width > 0, height > 0, width <= 8192, height <= 8192 else {
            throw ConversionError.invalidImage("Image exceeds the 8192-pixel analysis limit.")
        }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw ConversionError.invalidImage("Cannot allocate sRGB image context.") }
        pixels = data
        let alphaInfo = image.alphaInfo
        let hasAlpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(alphaInfo)
        geometry = ImageGeometry(width: width, height: height,
            sourceBitsPerComponent: image.bitsPerComponent,
            sourceColorSpace: image.colorSpace?.name as String? ?? "unspecified",
            sourceHasAlpha: hasAlpha,
            visibleBounds: Self.bounds(data, width: width, height: height, threshold: 1),
            solidBounds: Self.bounds(data, width: width, height: height, threshold: 128),
            transparentPixels: stride(from: 3, to: data.count, by: 4).filter { data[$0] == 0 }.count,
            opaquePixels: stride(from: 3, to: data.count, by: 4).filter { data[$0] == 255 }.count)
    }

    private static func bounds(_ pixels: [UInt8], width: Int, height: Int, threshold: UInt8) -> PixelBounds? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : PixelBounds(x: minX, y: minY, width: maxX-minX+1, height: maxY-minY+1)
    }

    public static func writePNG(pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard pixels.count == width * height * 4,
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ConversionError.invalidImage("Cannot create comparison PNG.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.invalidImage("Cannot save comparison PNG.") }
    }
}

public struct ImageComparison: Codable, Sendable {
    public let reference: ImageGeometry
    public let candidate: ImageGeometry
    public let normalizedExactMatch: Bool
    public let differentPixels: Int
    public let rgbaMeanAbsoluteError: Double
    public let alphaMeanAbsoluteError: Double
    public let maximumChannelDifference: Int
    public let maximumAlphaDifference: Int
    public let classification: String
    public let normalization: String

    public static func compare(reference: URL, candidate: URL, outputDirectory: URL) throws -> Self {
        let a = try RasterImage(url: reference), b = try RasterImage(url: candidate)
        guard a.width == b.width, a.height == b.height else {
            throw ConversionError.invalidImage("Canvas sizes differ: \(a.width)×\(a.height) and \(b.width)×\(b.height). No rescaling was applied.")
        }
        var sum = 0, alphaSum = 0, maximum = 0, alphaMax = 0, count = 0
        var difference = [UInt8](repeating: 255, count: a.pixels.count)
        var side = [UInt8](repeating: 0, count: a.pixels.count * 2)
        for pixel in 0..<(a.width * a.height) {
            var differs = false
            for c in 0..<4 {
                let offset = pixel * 4 + c
                let delta = abs(Int(a.pixels[offset]) - Int(b.pixels[offset]))
                sum += delta; maximum = max(maximum, delta); differs = differs || delta > 0
                if c == 3 { alphaSum += delta; alphaMax = max(alphaMax, delta) }
                else { difference[offset] = UInt8(delta) }
            }
            if differs { count += 1 }
            let y = pixel / a.width, x = pixel % a.width
            for c in 0..<4 {
                side[(y * a.width * 2 + x) * 4 + c] = a.pixels[pixel * 4 + c]
                side[(y * a.width * 2 + a.width + x) * 4 + c] = b.pixels[pixel * 4 + c]
            }
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try RasterImage.writePNG(pixels: difference, width: a.width, height: a.height, to: outputDirectory.appendingPathComponent("difference.png"))
        try RasterImage.writePNG(pixels: side, width: a.width * 2, height: a.height, to: outputDirectory.appendingPathComponent("side-by-side.png"))
        let report = Self(reference: a.geometry, candidate: b.geometry, normalizedExactMatch: count == 0,
            differentPixels: count, rgbaMeanAbsoluteError: Double(sum) / Double(a.pixels.count),
            alphaMeanAbsoluteError: Double(alphaSum) / Double(a.width * a.height),
            maximumChannelDifference: maximum, maximumAlphaDifference: alphaMax,
            classification: count == 0 ? "Exact after 8-bit sRGB normalization" : "Different; visual review required, fidelity not established",
            normalization: "Full-canvas 8-bit sRGB premultiplied RGBA via CoreGraphics; source files preserved. Color/profile/quantization differences may be removed or introduced. Bounds use alpha >= 1 and >= 128; y follows bitmap row order.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: outputDirectory.appendingPathComponent("comparison.json"), options: .atomic)
        return report
    }
}
