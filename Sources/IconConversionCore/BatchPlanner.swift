import Foundation

public struct PlannedConversion: Sendable {
    public let input: URL
    public let output: URL
}

public enum BatchPlanner {
    public static func plan(inputs: [URL], folder: URL, options: IconRenderOptions) -> [PlannedConversion] {
        var used = Set<String>()
        return inputs.map { input in
            let sourceName = input.deletingPathExtension().lastPathComponent
            let basename = "\(sourceName)-macOS-\(options.generation.rawValue)-\(options.appearance.displayName)"
            var name = basename, number = 2
            while !used.insert(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))).inserted {
                name = "\(basename) (\(number))"; number += 1
            }
            return PlannedConversion(input: input, output: folder.appendingPathComponent(name).appendingPathExtension("icns"))
        }
    }
}
