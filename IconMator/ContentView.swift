import AppKit
import IconConversionCore
import SwiftUI

struct ContentView: View {
    @State private var model = ConversionViewModel()
    @State private var isDropTarget = false
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            previewWorkspace
                .padding(20)
                .frame(maxHeight: .infinity)

            if model.jobs.count > 1 { batchTray }
            if let message = model.message { importMessage(message) }

            Divider()
            exportOptions
            Divider()
            bottomBar
        }
        .frame(minWidth: 560, minHeight: 620)
        .task { model.refreshTools() }
        .onDisappear { model.stopAllTasks() }
        .onOpenURL { model.importFiles([$0]) }
        .sheet(isPresented: $showDiagnostics) { diagnosticsSheet }
    }

    private var previewWorkspace: some View {
        VStack(spacing: 0) {
            if let job = model.selectedJob {
                HStack(spacing: 10) {
                    Text(job.input.deletingPathExtension().lastPathComponent)
                        .font(.headline).lineLimit(1).help(job.input.path)
                    Spacer()
                    Button("Add Files…", systemImage: "plus", action: model.selectFiles)
                        .keyboardShortcut("o")
                    Button("Remove Selected Icon", systemImage: "xmark", action: model.removeSelected)
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help("Remove selected icon")
                }
                .padding(16)
                .disabled(model.isConverting)

                Spacer(minLength: 8)
                selectedPreview(job)
                Spacer(minLength: 8)

                VStack(spacing: 6) {
                    Text(job.input.lastPathComponent).font(.callout).lineLimit(1)
                        .textSelection(.enabled)
                    Text(isDropTarget ? "Drop to import more icons" : job.status)
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = job.error {
                        Text(error).font(.callout).foregroundStyle(.red)
                            .textSelection(.enabled).lineLimit(3)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            } else {
                Spacer(minLength: 24)
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .padding(.bottom, 16)
                Text("Drop your .icon files here").font(.title2).fontWeight(.medium)
                Text("A rendered preview appears as soon as you import.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 6)
                Button("Choose Files…", action: model.selectFiles)
                    .keyboardShortcut("o").padding(.top, 20)
                Spacer(minLength: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isDropTarget ? Color.accentColor : Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1,
                        dash: model.selectedJob == nil ? [6, 5] : []))
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.isConverting else { return false }
            model.importFiles(urls)
            return urls.contains { $0.pathExtension.lowercased() == "icon" }
        } isTargeted: { isDropTarget = $0 }
    }

    @ViewBuilder private func selectedPreview(_ job: ConversionJob) -> some View {
        if let data = job.preview, job.previewOptions == model.renderOptions, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .frame(maxWidth: 280, maxHeight: 280)
                .accessibilityLabel("Rendered \(model.appearance.displayName) preview of \(job.input.lastPathComponent)")
        } else if model.isPreviewing {
            ProgressView("Rendering preview…").frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(model.toolIssue == nil ? "Preview unavailable" : "Preview requires developer tools")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private var batchTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(model.jobs.count) icons").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.jobs) { job in
                        Button { model.selection = job.id } label: {
                            VStack(spacing: 4) {
                                if let data = job.preview, job.previewOptions == model.renderOptions, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(width: 40, height: 40)
                                } else {
                                    Image(systemName: "app").font(.title).foregroundStyle(.secondary)
                                        .frame(width: 40, height: 40)
                                }
                                Text(job.input.deletingPathExtension().lastPathComponent)
                                    .font(.caption).lineLimit(1).frame(width: 76)
                            }
                            .padding(6)
                            .background(model.selection == job.id ? Color.primary.opacity(0.06) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(model.selection == job.id ? Color.accentColor : Color.clear)
                            }
                        }
                        .buttonStyle(.plain).help(job.input.path)
                        .accessibilityLabel("Preview \(job.input.lastPathComponent)")
                        .accessibilityAddTraits(model.selection == job.id ? [.isSelected] : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .disabled(model.isConverting)
    }

    private var exportOptions: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Export to").foregroundStyle(.secondary)
                Text(model.destination?.lastPathComponent ?? "Choose a folder")
                    .lineLimit(1).truncationMode(.middle)
                    .help(model.destination?.path ?? "Select an export folder")
                Spacer()
                Button(model.destination == nil ? "Choose Folder…" : "Change…", action: model.chooseDestination)
            }
            HStack(spacing: 10) {
                Toggle("Include PNG", isOn: $model.exportPNG)
                    .help("Export the same transparent 1024 × 1024 master used by the ICNS.")
                Spacer()
            }
            HStack(spacing: 10) {
                Text("Rendering").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .trailing)
                Picker("Rendering", selection: $model.generation) {
                    ForEach(IconDesignGeneration.allCases, id: \.rawValue) { generation in
                        Text(generation.displayName).tag(generation)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
                .help("Applies to the preview, PNG, and ICNS. macOS 26 uses the selected Xcode's Icon Composer renderer; the active macOS SDK remains 27.x.")
                .accessibilityLabel("Rendering generation")
                Spacer()
            }
            HStack(spacing: 10) {
                Text("Appearance").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .trailing)
                Picker("Appearance", selection: $model.appearance) {
                    ForEach(IconAppearance.allCases, id: \.rawValue) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
                .help("Applies independently of rendering generation. Dark and Mono use Apple's verified Icon Composer renditions.")
                .accessibilityLabel("Icon appearance")
                Spacer()
            }
            if let issue = model.renderIssue {
                Text(issue).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .disabled(model.isConverting)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Reveal in Finder") {
                if let output = model.revealTarget { model.reveal(output) }
            }
            .disabled(model.revealTarget == nil)
            Button("Diagnostics…") { showDiagnostics = true }

            footerStatus

            Group {
                if model.isConverting {
                    Button("Cancel", action: model.cancel)
                } else {
                    Button(model.jobs.count > 1 ? "Convert All" : "Convert to ICNS", action: model.startConversion)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!model.canConvert)
                }
            }
            .frame(width: 132, alignment: .trailing)
        }
        .controlSize(.regular)
        .frame(height: 28)
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var footerStatus: some View {
        HStack(spacing: 6) {
            if model.isConverting {
                ProgressView().controlSize(.mini).frame(width: 14, height: 14)
                Text("\(min(model.completed + 1, model.jobs.count)) of \(model.jobs.count) · \(model.currentStage)")
                    .help(model.currentStage)
            } else if model.isCheckingTools {
                Text("Checking developer tools…")
            } else if let issue = model.toolIssue {
                Text("Tools unavailable").foregroundStyle(.red).help(issue)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .lineLimit(1).truncationMode(.tail)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(height: 24)
        .accessibilityElement(children: .combine)
    }

    private func importMessage(_ message: String) -> some View {
        ScrollView {
            Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 64).padding(.horizontal, 20).padding(.bottom, 12)
    }

    private var diagnosticsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diagnostics").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rendering: \(model.renderOptions.generation.displayName)")
                    Text("Appearance: \(model.renderOptions.appearance.displayName)")
                    Text(model.toolStatus)
                    if let issue = model.toolIssue { Text(issue).foregroundStyle(.red) }
                    if let capabilities = model.renderCapabilities {
                        ForEach(capabilities.capabilities, id: \.options) { capability in
                            Text("\(capability.generation.displayName) · \(capability.appearance.displayName): \(capability.isSupported ? "available" : "unavailable") · \(capability.backend) · \(capability.rendition ?? "—")\(capability.reason.map { "\n\($0)" } ?? "")")
                                .foregroundStyle(capability.isSupported ? Color.secondary : Color.red)
                        }
                    }
                    Text("Rendering selects the material generation requested from Icon Composer. The final static image is presented by the current macOS host, so Finder-level presentation can still follow the host. macOS 27 + Default keeps the measured compiled-asset path on a macOS 27 host; macOS 26 and Dark/Mono use explicit Icon Composer renditions. No independent Finder reference is available for every source, and interactive visual acceptance was not performed.")
                        .foregroundStyle(.secondary)
                    if let job = model.selectedJob {
                        if let error = job.error { Text(error) }
                        Text(job.diagnostics.isEmpty ? "No conversion diagnostics for this icon yet." : job.diagnostics)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Recheck Tools", action: model.refreshTools)
                    .disabled(model.isConverting || model.isCheckingTools)
                Spacer()
                Button("Done") { showDiagnostics = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 600, height: 400)
    }
}
