import Foundation
import IconConversionCore

@main struct IconMatorCLI {
    private struct ToolsReport: Codable {
        let tools: DeveloperTools
        let appearanceCapabilities: AppearanceCapabilities
    }

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
                let capabilities = await AppearanceCapabilities.probe(tools: tools)
                print(String(decoding: try encoder.encode(ToolsReport(tools: tools, appearanceCapabilities: capabilities)), as: UTF8.self))
            } else if args.first == "convert" {
                let options = try CommandLineOptions.parseConvert(args)
                let service = IconConversionService()
                let tools = try await DeveloperToolLocator().locate()
                let result = try await service.convert(input: URL(fileURLWithPath: options.input),
                    destination: URL(fileURLWithPath: options.output), tools: tools,
                    appearance: options.appearance, exportPNG: options.exportPNG, overwrite: options.overwrite) { stage in
                        FileHandle.standardError.write(Data((stage.rawValue + "\n").utf8))
                    }
                print(result.icns.path)
                print(result.environment)
                if options.diagnostics { print(result.diagnostics) }
            } else if args.first == "package-png" {
                let options = try CommandLineOptions.parsePackagePNG(args)
                let service = IconConversionService()
                print(try await service.packagePNG(input: URL(fileURLWithPath: options.input),
                    destination: URL(fileURLWithPath: options.output), overwrite: options.overwrite).path)
            } else {
                throw ConversionError.invalidArguments(CommandLineOptions.usage)
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            if let detail = (error as? ConversionError)?.diagnostic { FileHandle.standardError.write(Data((detail + "\n").utf8)) }
            exit(1)
        }
    }
}
