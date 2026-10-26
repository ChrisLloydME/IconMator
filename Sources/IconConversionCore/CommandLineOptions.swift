import Foundation

public struct ConvertCommand: Sendable, Equatable {
    public let input: String
    public let output: String
    public let options: IconRenderOptions
    public let exportPNG: Bool
    public let overwrite: Bool
    public let diagnostics: Bool

    public init(input: String, output: String, options: IconRenderOptions, exportPNG: Bool,
                overwrite: Bool, diagnostics: Bool) {
        self.input = input
        self.output = output
        self.options = options
        self.exportPNG = exportPNG
        self.overwrite = overwrite
        self.diagnostics = diagnostics
    }

    public var generation: IconDesignGeneration { options.generation }
    public var appearance: IconAppearance { options.appearance }
}

public struct PackagePNGCommand: Sendable, Equatable {
    public let input: String
    public let output: String
    public let overwrite: Bool

    public init(input: String, output: String, overwrite: Bool) {
        self.input = input
        self.output = output
        self.overwrite = overwrite
    }
}

public enum CommandLineOptions {
    public static let usage = "Usage: iconmator tools | inspect image.png | compare reference.png candidate.png directory | convert input.icon output.icns [--generation 26|27] [--appearance default|dark|mono] [--png] [--replace] [--diagnostics] | package-png input.png output.icns [--replace]"

    public static func parseConvert(_ arguments: [String]) throws -> ConvertCommand {
        guard arguments.count >= 3, arguments[0] == "convert" else {
            throw ConversionError.invalidArguments("Expected: convert input.icon output.icns [--generation 26|27] [--appearance default|dark|mono] [--png] [--replace] [--diagnostics]")
        }
        var generation = IconDesignGeneration.macOS27
        var appearance = IconAppearance.default
        var sawGeneration = false
        var sawAppearance = false
        var exportPNG = false
        var overwrite = false
        var diagnostics = false
        var index = 3
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--generation":
                guard !sawGeneration else {
                    throw ConversionError.invalidArguments("Duplicate --generation option. Specify it once.")
                }
                guard index + 1 < arguments.count else {
                    throw ConversionError.invalidArguments("Missing value for --generation. Expected 26 or 27.")
                }
                let value = arguments[index + 1]
                guard !value.hasPrefix("--") else {
                    throw ConversionError.invalidArguments("Missing value for --generation. Expected 26 or 27.")
                }
                guard let parsed = IconDesignGeneration(cliValue: value) else {
                    throw ConversionError.invalidArguments("Invalid generation '\(value)'. Expected 26 or 27.")
                }
                generation = parsed
                sawGeneration = true
                index += 2
            case "--appearance":
                guard !sawAppearance else {
                    throw ConversionError.invalidArguments("Duplicate --appearance option. Specify it once.")
                }
                guard index + 1 < arguments.count else {
                    throw ConversionError.invalidArguments("Missing value for --appearance. Expected default, dark, or mono.")
                }
                let value = arguments[index + 1]
                guard !value.hasPrefix("--") else {
                    throw ConversionError.invalidArguments("Missing value for --appearance. Expected default, dark, or mono.")
                }
                guard let parsed = IconAppearance(rawValue: value) else {
                    throw ConversionError.invalidArguments("Invalid appearance '\(value)'. Expected default, dark, or mono.")
                }
                appearance = parsed
                sawAppearance = true
                index += 2
            case "--png":
                exportPNG = true
                index += 1
            case "--replace":
                overwrite = true
                index += 1
            case "--diagnostics":
                diagnostics = true
                index += 1
            default:
                throw ConversionError.invalidArguments("Unknown option '\(argument)'.\n\(usage)")
            }
        }
        return ConvertCommand(input: arguments[1], output: arguments[2],
            options: IconRenderOptions(generation: generation, appearance: appearance),
            exportPNG: exportPNG, overwrite: overwrite, diagnostics: diagnostics)
    }

    public static func parsePackagePNG(_ arguments: [String]) throws -> PackagePNGCommand {
        guard arguments.count >= 3, arguments[0] == "package-png" else {
            throw ConversionError.invalidArguments("Expected: package-png input.png output.icns [--replace]")
        }
        var overwrite = false
        for argument in arguments.dropFirst(3) {
            if argument == "--generation" || argument.hasPrefix("--generation=") {
                throw ConversionError.invalidArguments("package-png does not accept --generation; its input is already rendered.")
            }
            switch argument {
            case "--replace": overwrite = true
            case "--appearance":
                throw ConversionError.invalidArguments("package-png does not accept --appearance; its input is already rendered.")
            default: throw ConversionError.invalidArguments("Unknown option '\(argument)'.\n\(usage)")
            }
        }
        return PackagePNGCommand(input: arguments[1], output: arguments[2], overwrite: overwrite)
    }
}
