import Foundation
import Testing
@testable import IconConversionCore

struct ImageAnalysisTests {
    @Test func fullCanvasAlphaAndGeometry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        for y in 3..<13 { for x in 2..<14 { pixels[(y * 16 + x) * 4 + 3] = 255 } }
        let file = root.appendingPathComponent("图像 with spaces.png")
        try RasterImage.writePNG(pixels: pixels, width: 16, height: 16, to: file)
        let image = try RasterImage(url: file)
        #expect(image.geometry.sourceHasAlpha)
        #expect(image.geometry.visibleBounds == PixelBounds(x: 2, y: 3, width: 12, height: 10))
        #expect(image.geometry.transparentPixels == 136)
        let comparison = try ImageComparison.compare(reference: file, candidate: file, outputDirectory: root.appendingPathComponent("comparison"))
        #expect(comparison.normalizedExactMatch)
        #expect(comparison.alphaMeanAbsoluteError == 0)
    }

    @Test func doesNotHideCanvasChangesByCropping() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.png"), b = root.appendingPathComponent("b.png")
        try RasterImage.writePNG(pixels: [0, 0, 0, 255], width: 1, height: 1, to: a)
        try RasterImage.writePNG(pixels: [0, 0, 0, 255, 0, 0, 0, 0], width: 2, height: 1, to: b)
        #expect(throws: ConversionError.self) {
            try ImageComparison.compare(reference: a, candidate: b, outputDirectory: root)
        }
    }

    @Test func detectsAlphaDifferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.png"), b = root.appendingPathComponent("b.png")
        try RasterImage.writePNG(pixels: [0, 0, 0, 255], width: 1, height: 1, to: a)
        try RasterImage.writePNG(pixels: [0, 0, 0, 127], width: 1, height: 1, to: b)
        let result = try ImageComparison.compare(reference: a, candidate: b, outputDirectory: root.appendingPathComponent("diff"))
        #expect(!result.normalizedExactMatch)
        #expect(result.maximumAlphaDifference == 128)
    }
}
