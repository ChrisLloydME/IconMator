import Foundation

/// The macOS design generation requested from Icon Composer.
///
/// This is independent of the selected Xcode, the active macOS SDK and the
/// macOS version running IconMator. Selecting generation 26 does not switch
/// SDKs or alter the selected Xcode installation.
public enum IconDesignGeneration: Int, Codable, CaseIterable, Hashable, Sendable {
    case macOS26 = 26
    case macOS27 = 27

    public var displayName: String { "macOS \(rawValue)" }
    public var cliValue: String { String(rawValue) }

    public init?(cliValue: String) {
        switch cliValue {
        case "26": self = .macOS26
        case "27": self = .macOS27
        default: return nil
        }
    }
}

/// A complete rendering request. Generation and appearance are independent and
/// must travel together through preview, conversion and packaging.
public struct IconRenderOptions: Codable, Hashable, Sendable {
    public let generation: IconDesignGeneration
    public let appearance: IconAppearance

    public init(generation: IconDesignGeneration = .macOS27, appearance: IconAppearance = .default) {
        self.generation = generation
        self.appearance = appearance
    }

    /// Existing behavior on the researched macOS 27 host.
    public static let defaultOptions = IconRenderOptions()

    public var displayName: String {
        "\(generation.displayName) · \(appearance.displayName)"
    }
}
