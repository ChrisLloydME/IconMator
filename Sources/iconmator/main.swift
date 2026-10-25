import Foundation
import IconConversionCore

@main struct IconMatorCLI {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if args.count == 2, args[0] == "inspect" {
                let image = try RasterImage(url: URL(fileURLWithPath: args[1]))
                print(String(decoding: try encoder.encode(image.geometry), as: UTF8.self))
            } else if args.count == 4, args[0] == "compare" {
                let report = try ImageComparison.compare(reference: URL(fileURLWithPath: args[1]), candidate: URL(fileURLWithPath: args[2]), outputDirectory: URL(fileURLWithPath: args[3]))
                print(String(decoding: try encoder.encode(report), as: UTF8.self))
            } else {
                throw ConversionError.invalidInput("Usage: iconmator inspect image.png | compare reference.png candidate.png output-directory")
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
