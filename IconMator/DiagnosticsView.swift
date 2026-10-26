import AppKit
import IconConversionCore
import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: ConversionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Diagnostics").font(.title2.weight(.semibold))
                Text(model.renderOptions.displayName)
                    .font(.body).foregroundStyle(.primary)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let issue = model.toolIssue {
                        Text(issue).foregroundStyle(.red)
                    }
                    environmentSection
                    if let capabilities = model.renderCapabilities {
                        supportSection(capabilities)
                    }
                    logSection
                }
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    Button("Recheck Tools", action: model.refreshTools)
                        .disabled(model.isConverting || model.isCheckingTools)
                    Button("Copy Report", action: copyReport)
                    Spacer(minLength: 8)
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                .controlSize(.regular)
                .font(.body)
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 18)
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
        }
        .frame(width: 520, height: 560)
        .presentationBackground(.regularMaterial)
    }

    private var environmentRows: [(String, String)] {
        guard let tools = model.tools else { return [] }
        return [
            ("macOS", tools.operatingSystem),
            ("Xcode", tools.xcodeVersion.split(whereSeparator: \.isNewline).joined(separator: " · ")),
            ("SDK", "macOS \(tools.sdkVersion)"),
            ("Composer", tools.composerInfo?.displayVersion ?? "Unavailable"),
            ("Developer", tools.developerDirectory.path)
        ]
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Environment")
            sectionBody {
                if environmentRows.isEmpty {
                    Text(model.toolStatus).foregroundStyle(.primary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        ForEach(environmentRows, id: \.0) { row in
                            GridRow(alignment: .firstTextBaseline) {
                                Text(row.0).foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .leading)
                                Text(row.1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1).truncationMode(.middle).help(row.1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func supportSection(_ capabilities: RenderCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Rendering Support")
            sectionBody {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Generation").fontWeight(.medium)
                        ForEach(IconAppearance.allCases, id: \.rawValue) { appearance in
                            Text(appearance.displayName).fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(IconDesignGeneration.allCases, id: \.rawValue) { generation in
                        GridRow {
                            Text(generation.displayName)
                            ForEach(IconAppearance.allCases, id: \.rawValue) { appearance in
                                capabilityCell(capabilities.capability(for: IconRenderOptions(
                                    generation: generation, appearance: appearance)))
                            }
                        }
                    }
                }
            }
            ForEach(unavailableReasons(capabilities), id: \.self) { reason in
                Text(reason).font(.body).foregroundStyle(.red)
            }
            Text("Materials follow the selected rendering generation. The final canvas and shadows follow this Mac.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func capabilityCell(_ capability: RenderCapability?) -> some View {
        if let capability {
            Image(systemName: capability.isSupported ? "checkmark" : "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(capability.isSupported ? Color.green : Color.red)
                .frame(maxWidth: .infinity, minHeight: 20)
                .help(capability.reason ?? capability.backend)
                .accessibilityLabel("\(capability.generation.displayName), \(capability.appearance.displayName): \(capability.isSupported ? "Available" : "Unavailable")")
        } else {
            Image(systemName: "minus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 20)
                .accessibilityLabel("Not checked")
        }
    }

    private func unavailableReasons(_ capabilities: RenderCapabilities) -> [String] {
        Array(Set(capabilities.capabilities.compactMap { $0.isSupported ? nil : $0.reason })).sorted()
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionTitle("Conversion Log")
                Spacer(minLength: 8)
                if let job = model.selectedJob {
                    Text(job.input.lastPathComponent)
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(job.input.path)
                }
            }
            sectionBody {
                VStack(alignment: .leading, spacing: 8) {
                    if let job = model.selectedJob, let error = job.error {
                        Text(error).foregroundStyle(.red)
                    }
                    if let job = model.selectedJob, !job.diagnostics.isEmpty {
                        Text(job.diagnostics)
                            .font(.system(.callout, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Convert an icon to collect its log.").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func sectionBody<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private func copyReport() {
        var lines = ["IconMator Diagnostics", "Rendering: \(model.generation.displayName)",
                     "Appearance: \(model.appearance.displayName)", ""]
        if environmentRows.isEmpty { lines.append(model.toolStatus) }
        lines += environmentRows.map { "\($0.0): \($0.1)" }
        if let tools = model.tools, let composer = tools.composerTool {
            lines.append("Composer executable: \(composer.path)")
        }
        if let issue = model.toolIssue { lines.append("Tool issue: \(issue)") }
        if let capabilities = model.renderCapabilities {
            lines += ["", "Rendering Support"]
            lines += capabilities.capabilities.map { capability in
                "\(capability.options.displayName): \(capability.isSupported ? "Available" : "Unavailable") · \(capability.backend) · \(capability.rendition ?? "—")\(capability.reason.map { " · \($0)" } ?? "")"
            }
        }
        if let job = model.selectedJob {
            lines += ["", "Input: \(job.input.path)", "Status: \(job.status)"]
            if let error = job.error { lines.append(error) }
            if !job.diagnostics.isEmpty { lines.append(job.diagnostics) }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
