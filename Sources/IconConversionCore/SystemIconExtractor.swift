import AppKit
import CoreGraphics
import Foundation

/// Shared system-icon extraction. Both the compiled-asset and Composer backends
/// hand a complete temporary application bundle to IconServices and receive the
/// final macOS application-icon canvas.
enum SystemIconExtractor {
    @MainActor
    static func extract(bundle: URL, to iconset: URL) throws -> String {
        var diagnostics = ""
        var extractionError: Error?
        guard let appearance = NSAppearance(named: .aqua) else {
            throw ConversionError.validation("Default appearance is unavailable.")
        }
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
                    diagnostics += "System request \(rep.pixels)px: source \(source.width)×\(source.height), \(source.bitsPerComponent) bits/component\n"
                    let result = try normalizedSRGB(source, width: rep.pixels, height: rep.pixels)
                    if rep.pixels == 1024 {
                        let generic = NSWorkspace.shared.icon(for: .applicationBundle)
                        var genericRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
                        guard let genericSource = generic.cgImage(forProposedRect: &genericRect, context: nil, hints: nil) else {
                            throw ConversionError.validation("Cannot validate the system icon against its generic fallback.")
                        }
                        let genericImage = try normalizedSRGB(genericSource, width: 1024, height: 1024)
                        if let genericData = genericImage.dataProvider?.data, let resultData = result.dataProvider?.data,
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

    /// Converts the complete source canvas into explicit 8-bit premultiplied
    /// sRGB. Extended-range sources use CoreGraphics' documented `.none` tone
    /// mapping policy, matching the existing Default extraction path.
    static func normalizedSRGB(_ source: CGImage, width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw ConversionError.invalidImage("Cannot allocate rendering context.")
        }
        context.interpolationQuality = .high
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        if source.shouldToneMap {
            guard context.draw(source, in: target, by: .none, options: nil) else {
                throw ConversionError.invalidImage("Cannot export extended-range system icon.")
            }
        } else {
            context.draw(source, in: target)
        }
        guard let result = context.makeImage() else {
            throw ConversionError.invalidImage("System icon export failed.")
        }
        return result
    }
}
