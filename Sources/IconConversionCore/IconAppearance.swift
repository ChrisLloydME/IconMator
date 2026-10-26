import Foundation

/// The three appearance choices exposed by IconMator.
///
/// `mono` is the user's previous "Clear" appearance. The renderer calls the
/// untinted light variant `ClearLight`; `ClearDark` is a separate variant and is
/// intentionally not exposed by this single-choice control.
public enum IconAppearance: String, Codable, CaseIterable, Sendable, Hashable {
    case `default`
    case dark
    case mono

    public var displayName: String {
        switch self {
        case .default: return "Default"
        case .dark: return "Dark"
        case .mono: return "Mono"
        }
    }

    /// The explicit, experimentally verified Icon Composer rendition.
    ///
    /// Default is normally handled by `CompiledAssetBackend`; the mapping is
    /// still defined here so capability reporting and diagnostics never build
    /// renderer arguments from UI strings.
    public var composerRendition: ComposerRendition? {
        switch self {
        case .default: return .default
        case .dark: return .dark
        case .mono: return .clearLight
        }
    }
}

/// Rendition identifiers accepted by the selected Xcode's Icon Composer renderer.
/// Values are deliberately explicit rather than user-facing display strings.
public enum ComposerRendition: String, Sendable, Equatable, CaseIterable {
    case `default` = "Default"
    case dark = "Dark"
    case tintedLight = "TintedLight"
    case tintedDark = "TintedDark"
    case clearLight = "ClearLight"
    case clearDark = "ClearDark"
}
