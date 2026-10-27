import Foundation
import IconConversionCore

enum WelcomeProgress {
    static let completionKey = "welcome.completedVersion"
    static let currentVersion = 1

    static func shouldPresent(completedVersion: Int) -> Bool {
        completedVersion < currentVersion
    }
}

enum WelcomePage: Int, CaseIterable {
    case introduction, environment
}

struct WelcomeRequirement: Identifiable {
    enum State { case checking, passed, limited, failed, notChecked }
    enum Kind: String { case macOS, xcode, sdk, composer }

    let id: Kind
    let title: String
    let detail: String
    let state: State
}

/// Presents the same SDK policy and rendering capabilities used by conversion.
/// This is tool preflight, not a claim that a reference rendering was compared.
struct WelcomeEnvironmentReport {
    enum Readiness { case checking, ready, limited, unavailable }

    let readiness: Readiness
    let requirements: [WelcomeRequirement]
    let issue: String?

    init(tools: DeveloperTools?, isChecking: Bool, issue: String?,
         systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) {
        let capabilities = tools.map(RenderCapabilities.probe)
        self.issue = issue ?? capabilities?.capabilities.first(where: { !$0.isSupported })?.reason
        let systemSupported = systemVersion.majorVersion >= 26
        let systemName = "macOS \(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)"
        let sdkSupported = tools.map { (try? $0.requireSupportedSDK()) != nil } ?? false
        let supportedModes = capabilities?.capabilities.filter(\.isSupported).count ?? 0
        if isChecking {
            readiness = .checking
        } else if !systemSupported || issue != nil || !sdkSupported || supportedModes == 0 {
            readiness = .unavailable
        } else {
            readiness = supportedModes == 6 ? .ready : .limited
        }

        let waiting: WelcomeRequirement.State = isChecking ? .checking : .notChecked
        let composerDetail: String
        let composerState: WelcomeRequirement.State
        if !isChecking, tools != nil, !sdkSupported {
            composerDetail = "Select a macOS SDK 27 toolchain to enable rendering."
            composerState = .notChecked
        } else if let tools, !isChecking {
            if supportedModes == 6 {
                composerDetail = "Icon Composer \(tools.composerInfo?.displayVersion ?? "") · All six rendering options available."
                composerState = .passed
            } else {
                composerDetail = supportedModes > 0
                    ? "macOS 27 Default is available. Other options need a compatible Icon Composer."
                    : "A compatible Icon Composer is needed for the available rendering options."
                composerState = supportedModes > 0 ? .limited : .failed
            }
        } else {
            composerDetail = isChecking ? "Checking rendering capabilities…" : "Checked after Xcode is available."
            composerState = waiting
        }

        requirements = [
            WelcomeRequirement(id: .macOS, title: "macOS 26 or later", detail: systemName,
                               state: systemSupported ? .passed : .failed),
            WelcomeRequirement(id: .xcode, title: "A full Xcode installation",
                               detail: tools.map { $0.xcodeVersion.split(whereSeparator: \.isNewline).joined(separator: " · ") }
                                   ?? (isChecking ? "Looking for the selected Xcode…" : "Install and open Xcode, then select its developer tools."),
                               state: tools != nil ? .passed : (issue != nil ? .failed : waiting)),
            WelcomeRequirement(id: .sdk, title: "macOS SDK 27",
                               detail: tools.map { sdkSupported
                                   ? "Detected \($0.sdkVersion) · Beta and RC releases are supported."
                                   : "Detected \($0.sdkVersion). Select Xcode with a macOS SDK from the 27 family." }
                                   ?? (isChecking ? "Checking the active macOS SDK…" : "Checked after Xcode is available."),
                               state: tools != nil ? (sdkSupported ? .passed : .failed) : waiting),
            WelcomeRequirement(id: .composer, title: "Icon Composer with 26 / 27 rendering",
                               detail: composerDetail, state: composerState)
        ]
    }

    var title: String {
        switch readiness {
        case .checking: "Checking your Mac…"
        case .ready: "Your Mac is ready"
        case .limited: "Some rendering options are available"
        case .unavailable: "A little setup is needed"
        }
    }

    var detail: String {
        switch readiness {
        case .checking: "Looking for Apple's tools. You can continue while this finishes."
        case .ready: "The required tools and all six rendering options are available."
        case .limited: "You can use macOS 27 Default now and set up the other options later."
        case .unavailable: "You can open IconMator now. Conversion stays unavailable until its requirements are met."
        }
    }
}
