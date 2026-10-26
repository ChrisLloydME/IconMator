import Foundation
import IconConversionCore
import Testing
@testable import IconMatorPresentation

private actor PreviewRequests {
    var paths: [String] = []
    func record(_ url: URL) { paths.append(url.path) }
}

@MainActor struct ImportWorkflowTests {
    @Test func pickerAcceptsDirectoryDocumentsAndKeepsFoldersNavigable() throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let document = try makeIcon("Composer Document.icon", in: workspace.url)
        let folder = workspace.url.appendingPathComponent("Ordinary Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let png = workspace.url.appendingPathComponent("image.png")
        try Data().write(to: png)
        let delegate = IconImportPanelDelegate()
        #expect(delegate.panel(0, shouldEnable: document))
        #expect(delegate.panel(0, shouldEnable: folder))
        #expect(!delegate.panel(0, shouldEnable: png))
        try delegate.panel(0, validate: document)
        #expect(throws: ConversionError.self) { try delegate.panel(0, validate: folder) }
        #expect(throws: ConversionError.self) { try delegate.panel(0, validate: png) }
    }

    @Test func pickerRejectsMalformedIconDirectories() throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let invalid = workspace.url.appendingPathComponent("Invalid.icon", isDirectory: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: false)
        #expect(throws: ConversionError.self) { try IconImportPanelDelegate().panel(0, validate: invalid) }
    }

    @Test func newImportIsSelectedAndAutomaticallyRequestsItsPreview() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let first = try makeIcon("First.icon", in: workspace.url)
        let second = try makeIcon("Second.icon", in: workspace.url)
        let requests = PreviewRequests()
        // Only the presentation trigger is mocked. Rendering remains covered by real-tool integration tests.
        let model = ConversionViewModel(externalToolsPermitted: true) { url, _, _ in
            await requests.record(url)
            return Data(url.lastPathComponent.utf8)
        }
        model.tools = try fixtureTools()
        model.importFiles([first])
        for _ in 0..<100 where model.selectedJob?.preview == nil { await Task.yield() }
        #expect(model.selectedJob?.preview == Data("First.icon".utf8))
        model.importFiles([second])
        for _ in 0..<100 where model.selectedJob?.preview == nil { await Task.yield() }
        #expect(model.jobs.count == 2)
        #expect(model.selectedJob?.input.path == second.path)
        #expect(model.selectedJob?.preview == Data("Second.icon".utf8))
        #expect(await requests.paths == [first.path, second.path])
        #expect(!model.isPreviewing)
        model.stopAllTasks()
    }

    @Test func duplicateImportSelectsExistingJobWithoutAddingAnother() throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let first = try makeIcon("First.icon", in: workspace.url)
        let second = try makeIcon("Second.icon", in: workspace.url)
        let model = ConversionViewModel(externalToolsPermitted: true)
        model.importFiles([first, second])
        model.selection = model.jobs[1].id
        model.importFiles([first])
        #expect(model.jobs.count == 2)
        #expect(model.selectedJob?.input.path == first.path)
    }

    private func makeIcon(_ name: String, in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try Data("{\"groups\":[]}".utf8).write(to: url.appendingPathComponent("icon.json"))
        return url
    }

    private func fixtureTools() throws -> DeveloperTools {
        DeveloperTools(developerDirectory: URL(fileURLWithPath: "/fixture/Xcode/Contents/Developer"),
            xcodebuild: URL(fileURLWithPath: "/fixture/xcodebuild"),
            actool: URL(fileURLWithPath: "/fixture/actool"),
            clang: URL(fileURLWithPath: "/fixture/clang"),
            sdk: URL(fileURLWithPath: "/fixture/SDK"), sdkVersion: "27.0",
            iconutil: URL(fileURLWithPath: "/usr/bin/iconutil"),
            composerTool: URL(fileURLWithPath: "/usr/bin/true"),
            composerInfo: ComposerToolInfo(path: "/usr/bin/true", shortVersion: "27.1", buildVersion: "129",
                interface: ComposerInterfaceCapabilities(exportImage: true, rendition: true, designGeneration: true)),
            xcodeVersion: "fixture", operatingSystem: "27.0.1 (26A434)")
    }
}
