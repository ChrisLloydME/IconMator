import AppKit
import IconConversionCore
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var model = ConversionViewModel()
    @State private var isDropTarget = false
    @State private var presentedSheet: PresentedSheet?
    @AppStorage(WelcomeProgress.completionKey) private var completedWelcomeVersion = 0

    private enum PresentedSheet: String, Identifiable {
        case welcome, diagnostics
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 16) {
            windowHeader
            previewWorkspace
                .frame(maxHeight: .infinity)
            if model.jobs.count > 1 { batchTray }
            if let message = model.message { importMessage(message) }
            exportDestination
            Divider()
            bottomBar
        }
        .font(.body)
        .padding(20)
        .frame(minWidth: 520, minHeight: 540)
        .task {
            model.refreshTools()
            if WelcomeProgress.shouldPresent(completedVersion: completedWelcomeVersion) {
                presentedSheet = .welcome
            }
        }
        .onDisappear { model.stopAllTasks() }
        .onOpenURL { model.importFiles([$0]) }
        .focusedSceneValue(\.showWelcome, model.isConverting ? nil : {
            presentedSheet = .welcome
        })
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .welcome:
                WelcomeView(model: model) {
                    completedWelcomeVersion = WelcomeProgress.currentVersion
                    presentedSheet = nil
                }
            case .diagnostics:
                DiagnosticsView(model: model)
            }
        }
    }

    private var windowHeader: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Text("IconMator").font(.title2.weight(.semibold))
            Spacer(minLength: 16)
            Picker("Rendering", selection: $model.generation) {
                ForEach(IconDesignGeneration.allCases, id: \.rawValue) { generation in
                    Text(generation.displayName).tag(generation)
                }
            }
            .frame(width: 112)
            .help("Choose macOS 26 or macOS 27 rendering for the preview and export.")
            Picker("Appearance", selection: $model.appearance) {
                ForEach(IconAppearance.allCases, id: \.rawValue) { appearance in
                    Label {
                        Text(appearance.displayName)
                    } icon: {
                        Image(systemName: appearanceSymbol(appearance)).fontWeight(.medium)
                    }
                    .tag(appearance)
                }
            }
            .frame(width: 112)
            .help("Choose Default, Dark, or Mono for the preview and export.")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.body)
        .controlSize(.regular)
        .disabled(model.isConverting)
    }

    private func appearanceSymbol(_ appearance: IconAppearance) -> String {
        switch appearance {
        case .default: "sun.max"
        case .dark: "moon"
        case .mono: "circle.lefthalf.filled"
        }
    }

    private var previewWorkspace: some View {
        VStack(spacing: 12) {
            if let job = model.selectedJob {
                HStack(spacing: 12) {
                    Text(job.input.deletingPathExtension().lastPathComponent)
                        .font(.body).foregroundStyle(.primary)
                        .lineLimit(1).help(job.input.path)
                    Spacer(minLength: 8)
                    Button("Add Files…", systemImage: "plus", action: model.selectFiles)
                        .fontWeight(.medium)
                        .keyboardShortcut("o")
                        .help("Add Icon Composer files")
                    Button("Remove Selected Icon", systemImage: "xmark", action: model.removeSelected)
                        .fontWeight(.medium)
                        .help("Remove selected icon")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(model.isConverting)

                selectedPreview(job)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 5) {
                    Text(isDropTarget ? "Drop to add more icons" : job.status)
                        .font(.body).foregroundStyle(.primary)
                    if let error = job.error {
                        Text(error).font(.body).foregroundStyle(.red)
                            .textSelection(.enabled).lineLimit(3)
                    } else if let issue = model.renderIssue {
                        Text(issue).font(.body).foregroundStyle(.red)
                            .textSelection(.enabled).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                Spacer(minLength: 12)
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .padding(.bottom, 4)
                Text("Drop an icon").font(.title2.weight(.semibold))
                Text(".icon files from Icon Composer")
                    .font(.body).foregroundStyle(.secondary)
                Button("Choose Files…", action: model.selectFiles)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .font(.body)
                    .keyboardShortcut("o")
                    .padding(.top, 8)
                Spacer(minLength: 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.14 : 0.06))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 2)
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
                .frame(maxWidth: 256, maxHeight: 256)
                .accessibilityLabel("\(model.generation.displayName) \(model.appearance.displayName) preview of \(job.input.lastPathComponent)")
        } else if model.isPreviewing {
            ProgressView("Rendering preview…")
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo").font(.system(size: 28, weight: .medium)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(model.toolIssue == nil ? "Preview unavailable" : "Preview requires developer tools")
                    .font(.body).foregroundStyle(.secondary)
            }
        }
    }

    private var batchTray: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.jobs) { job in
                    Button { model.selection = job.id } label: {
                        VStack(spacing: 4) {
                            if let data = job.preview, job.previewOptions == model.renderOptions, let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 36)
                            } else {
                                Image(systemName: "app").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                                    .frame(width: 36, height: 36)
                            }
                            Text(job.input.deletingPathExtension().lastPathComponent)
                                .font(.body).lineLimit(1).frame(width: 76)
                        }
                        .padding(6)
                        .background(model.selection == job.id ? Color.primary.opacity(0.07) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain).help(job.input.path)
                    .accessibilityLabel("Preview \(job.input.lastPathComponent)")
                    .accessibilityAddTraits(model.selection == job.id ? [.isSelected] : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 72)
        .disabled(model.isConverting)
    }

    private var exportDestination: some View {
        @Bindable var model = model
        return HStack(spacing: 16) {
            Button(action: model.chooseDestination) {
                HStack(spacing: 8) {
                    Image(systemName: "folder").fontWeight(.medium).foregroundStyle(.secondary)
                    Text(model.destination?.lastPathComponent ?? "Export folder…")
                        .lineLimit(1).truncationMode(.middle)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .help(model.destination?.path ?? "Choose an export folder")
            .accessibilityLabel("Export folder")
            .accessibilityValue(model.destination?.path ?? "Not selected")
            Spacer(minLength: 8)
            Toggle("Include PNG", isOn: $model.exportPNG)
                .fixedSize()
                .help("Save the same transparent 1024 × 1024 image used by the ICNS.")
        }
        .font(.body)
        .controlSize(.regular)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .disabled(model.isConverting)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button("Reveal in Finder") {
                if let output = model.revealTarget { model.reveal(output) }
            }
            .disabled(model.revealTarget == nil)
            Button("Diagnostics…") { presentedSheet = .diagnostics }
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
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .font(.body)
            .frame(width: 132, alignment: .trailing)
        }
        .buttonStyle(.bordered)
        .font(.body)
        .controlSize(.regular)
        .frame(height: 30)
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
        .font(.body).foregroundStyle(.secondary)
        .lineLimit(1).truncationMode(.tail)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(height: 24)
        .accessibilityElement(children: .combine)
    }

    private func importMessage(_ message: String) -> some View {
        ScrollView {
            Text(message).font(.body).foregroundStyle(.red).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 54)
    }

}
