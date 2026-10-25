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
            } else if args == ["tools"] {
                let tools = try await DeveloperToolLocator().locate()
                print(String(decoding: try encoder.encode(tools), as: UTF8.self))
            } else if args.count >= 3, args[0] == "convert" || args[0] == "package-png" {
                let options = args[0] == "convert" ? ["--replace", "--png", "--diagnostics"] : ["--replace"]
                guard args.dropFirst(3).allSatisfy({ options.contains($0) }) else {
                    throw ConversionError.invalidInput("Unknown option.")
                }
                let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
                let service = IconConversionService()
                if args[0] == "package-png" {
                    print(try await service.packagePNG(input: input, destination: output, overwrite: args.contains("--replace")).path)
                } else {
                    let tools = try await DeveloperToolLocator().locate()
                    let result = try await service.convert(input: input, destination: output, tools: tools, exportPNG: args.contains("--png"), overwrite: args.contains("--replace")) { stage in
                        FileHandle.standardError.write(Data((stage.rawValue + "\n").utf8))
                    }
                    print(result.icns.path)
                    print(result.environment)
                    if args.contains("--diagnostics") { print(result.diagnostics) }
                }
            } else {
                throw ConversionError.invalidInput("Usage: iconmator tools | inspect image.png | compare reference.png candidate.png directory | convert input.icon output.icns [--png] [--replace] [--diagnostics] | package-png input.png output.icns [--replace]")
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            if let detail = (error as? ConversionError)?.diagnostic { FileHandle.standardError.write(Data((detail + "\n").utf8)) }
            exit(1)
        }
    }
}
