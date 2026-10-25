import AppKit
import SwiftUI

struct ContentView: View {
    @State private var model = ConversionViewModel()
    @State private var isDropTarget = false
    @State private var showDiagnostics = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down").font(.title2).accessibilityHidden(true)
                    Text("Drop .icon files here")
                    Button("Choose Files…", action: model.selectFiles).keyboardShortcut("o")
                }
                .frame(maxWidth: .infinity).padding(20)
                .background(isDropTarget ? Color.accentColor.opacity(0.12) : Color.clear)
                .dropDestination(for: URL.self) { urls, _ in
                    guard !model.isConverting else { return false }
                    model.importFiles(urls)
                    return urls.contains { $0.pathExtension.lowercased() == "icon" }
                } isTargeted: { isDropTarget = $0 }
                Divider()
                List(selection: $model.selection) {
                    ForEach(model.jobs) { job in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.input.deletingPathExtension().lastPathComponent).lineLimit(1)
                            Text(job.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.tag(job.id).help(job.input.path)
                    }
                }.accessibilityLabel("Imported icons")
                HStack {
                    Text("\(model.jobs.count) icon\(model.jobs.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove", systemImage: "minus", action: model.removeSelected)
                        .labelStyle(.iconOnly).disabled(model.selection == nil || model.isConverting)
                }.padding(10)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340).disabled(model.isConverting)
        } detail: {
            VStack(spacing: 18) {
                if let job = model.selectedJob {
                    if let data = job.preview, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .frame(maxWidth: 280, maxHeight: 280)
                            .accessibilityLabel("Rendered preview of \(job.input.lastPathComponent)")
                    } else if model.isPreviewing {
                        ProgressView("Rendering preview…").frame(height: 280)
                    } else {
                        ContentUnavailableView("Preview unavailable", systemImage: "photo", description: Text("A preview uses the same system renderer as the exported icon.")).frame(height: 280)
                    }
                    Text(job.input.lastPathComponent).font(.title3).textSelection(.enabled)
                    if let error = job.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    if let output = job.output { Button("Reveal in Finder", systemImage: "folder") { model.reveal(output) } }
                    if !job.diagnostics.isEmpty { Button("Show Diagnostics…") { showDiagnostics = true } }
                } else {
                    ContentUnavailableView("Import an Icon Composer file", systemImage: "app.dashed", description: Text("Render a static macOS Default icon and export it as ICNS.")).frame(maxHeight: .infinity)
                }
                Spacer(minLength: 0)
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Appearance", value: "macOS Default · current renderer")
                        Toggle("Also export the 1024 × 1024 PNG", isOn: $model.exportPNG)
                        HStack {
                            Text(model.destination?.path(percentEncoded: false) ?? "Choose an export folder")
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).help(model.destination?.path ?? "")
                            Spacer()
                            Button("Choose Folder…", action: model.chooseDestination)
                        }
                    }.padding(6)
                }.disabled(model.isConverting)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(model.toolStatus).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Recheck Tools", action: model.refreshTools).font(.caption)
                            .disabled(model.isConverting || model.isCheckingTools)
                    }
                    if let issue = model.toolIssue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    Text("Experimental: small differences from the Finder reference remain. Dark, Mono and other OS renderers are not yet validated.").font(.caption).foregroundStyle(.secondary)
                }
                if let message = model.message { Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                HStack {
                    if model.isConverting {
                        ProgressView().controlSize(.small)
                        Text("\(model.completed + 1)/\(model.jobs.count) · \(model.currentStage)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", action: model.cancel)
                    } else {
                        Spacer()
                        Button(model.jobs.count > 1 ? "Convert All to ICNS" : "Convert to ICNS", action: model.startConversion)
                            .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command).disabled(!model.canConvert)
                    }
                }
            }.padding(24).frame(minWidth: 420)
        }
        .frame(minWidth: 760, minHeight: 660)
        .task { model.refreshTools() }
        .onChange(of: model.selection) { _, _ in model.renderSelectedPreview() }
        .onDisappear { model.stopAllTasks() }
        .onOpenURL { model.importFiles([$0]) }
        .sheet(isPresented: $showDiagnostics) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Conversion Diagnostics").font(.headline)
                ScrollView {
                    Text(model.selectedJob?.diagnostics ?? "No diagnostics available.")
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Done") { showDiagnostics = false }.keyboardShortcut(.defaultAction)
            }.padding(24).frame(width: 640, height: 400)
        }
    }
}
