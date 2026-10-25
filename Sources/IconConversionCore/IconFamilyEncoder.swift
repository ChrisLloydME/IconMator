import Foundation

/// Conventional ICNS container with PNG renditions plus Apple's observed ic04/ic05 ARGB codec.
/// On Xcode 27.1, iconutil's encoder associates alpha incorrectly for those two chunks.
/// Explicit premultiplied ARGB planes avoid that defect. Every output is decoded by iconutil and compared.
enum IconFamilyEncoder {
    static func encode(iconset: URL) throws -> Data {
        var body = Data()
        for rep in IconRepresentation.standard {
            let url = iconset.appendingPathComponent(rep.name)
            let payload: Data
            if rep.chunk == "ic04" || rep.chunk == "ic05" {
                let raster = try RasterImage(url: url)
                guard raster.width == rep.pixels, raster.height == rep.pixels else {
                    throw ConversionError.validation("Incorrect ARGB rendition dimensions.")
                }
                payload = encodeARGB(raster.pixels)
            } else {
                payload = try Data(contentsOf: url)
                guard payload.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
                    throw ConversionError.validation("A non-PNG rendition was supplied for \(rep.name).")
                }
            }
            body.append(contentsOf: rep.chunk.utf8)
            body.append(try length(payload.count + 8))
            body.append(payload)
        }
        var file = Data("icns".utf8)
        file.append(try length(body.count + 8))
        file.append(body)
        return file
    }

    /// ARGB, four PackBits-style channel planes. Literal packets contain 1...128 bytes.
    static func encodeARGB(_ rgba: [UInt8]) -> Data {
        var result = Data("ARGB".utf8)
        for channel in [3, 0, 1, 2] {
            let plane = stride(from: channel, to: rgba.count, by: 4).map { rgba[$0] }
            for start in stride(from: 0, to: plane.count, by: 128) {
                let end = min(start + 128, plane.count)
                result.append(UInt8(end - start - 1))
                result.append(contentsOf: plane[start..<end])
            }
        }
        return result
    }

    private static func length(_ size: Int) throws -> Data {
        guard let value = UInt32(exactly: size) else { throw ConversionError.validation("ICNS is too large.") }
        return withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
