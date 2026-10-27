import AppKit
import IconConversionCore
import SwiftUI

struct WelcomeView: View {
    let model: ConversionViewModel
    let onFinish: () -> Void
    @State private var page: WelcomePage = .introduction

    private var report: WelcomeEnvironmentReport {
        WelcomeEnvironmentReport(tools: model.detectedTools ?? model.tools,
                                 isChecking: model.isCheckingTools, issue: model.toolIssue)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if page == .introduction {
                        introduction
                    } else {
                        environment
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.top, 28)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            navigation
        }
        .frame(width: 640, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(page == .introduction ? "Welcome to IconMator" : "Check your Mac")
                    .font(.system(size: 30, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(page == .introduction
                     ? "Turn Icon Composer files into ready-to-use Mac icons."
                     : "IconMator uses Apple's developer tools to render your icons. Let's check what's available.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 24) {
                feature("From .icon to .icns", symbol: "square.and.arrow.down",
                        detail: "Drop in an Icon Composer file, preview it, and export a complete Mac icon.")
                feature("Choose the look", symbol: "circle.lefthalf.filled",
                        detail: "macOS 26 or 27 rendering, in Default, Dark, or Mono.")
                feature("Keep your originals", symbol: "doc.on.doc",
                        detail: "Export one icon or a batch with transparency. Your source files stay untouched.")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            Text("Everything happens locally on your Mac. No uploads or account required.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func feature(_ title: String, symbol: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var environment: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                if report.readiness == .checking {
                    ProgressView().controlSize(.small).frame(width: 20, height: 20)
                } else {
                    Image(systemName: report.readiness == .ready ? "checkmark.circle.fill" : "info.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(report.readiness == .ready ? Color.green : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.title).font(.headline)
                    Text(report.detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Recheck", action: model.refreshTools)
                    .disabled(model.isCheckingTools || model.isConverting)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(report.requirements) { requirement in
                    requirementRow(requirement)
                    if requirement.id != .composer { Divider().padding(.leading, 42) }
                }
            }
            .padding(.horizontal, 18)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

            if let issue = report.issue {
                DisclosureGroup("Setup details") {
                    Text(issue).font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .font(.callout)
            }
            Text("This checks installed tools and rendering options. Each exported icon is verified before it is saved.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func requirementRow(_ requirement: WelcomeRequirement) -> some View {
        HStack(alignment: .top, spacing: 14) {
            requirementIndicator(requirement.state)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(requirement.title).font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(statusLabel(requirement.state)).font(.caption).foregroundStyle(.secondary)
                }
                Text(requirement.detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func requirementIndicator(_ state: WelcomeRequirement.State) -> some View {
        switch state {
        case .checking: ProgressView().controlSize(.mini)
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .limited: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .notChecked: Image(systemName: "minus.circle").foregroundStyle(.tertiary)
        }
    }

    private func statusLabel(_ state: WelcomeRequirement.State) -> String {
        switch state {
        case .checking: "Checking"
        case .passed: "Ready"
        case .limited: "Limited"
        case .failed: "Needs setup"
        case .notChecked: "Not checked"
        }
    }

    private var navigation: some View {
        HStack {
            Button(page == .introduction ? "Quit" : "Back") {
                if page == .introduction { NSApplication.shared.terminate(nil) }
                else { page = .introduction }
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .frame(minWidth: 116)
            Spacer()
            Text("\(page.rawValue + 1) of \(WelcomePage.allCases.count)")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel("Step \(page.rawValue + 1) of \(WelcomePage.allCases.count)")
            Spacer()
            Button(primaryButtonTitle) {
                if page == .introduction { page = .environment }
                else { onFinish() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .frame(minWidth: 116)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .padding(.horizontal, 30)
        .padding(.top, 14)
        .padding(.bottom, 26)
    }

    private var primaryButtonTitle: String {
        if page == .introduction { return "Continue" }
        return report.readiness == .ready ? "Get Started" : "Open IconMator"
    }
}
