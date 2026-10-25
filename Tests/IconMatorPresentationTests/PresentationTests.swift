import Foundation
import IconConversionCore
import Testing
@testable import IconMatorPresentation

@MainActor struct PresentationTests {
    @Test func importingDeduplicatesAndRemovalKeepsSelectionValid() throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = workspace.url.appendingPathComponent("应用.icon")
        try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: false)
        try Data("{\"groups\":[]}".utf8).write(to: icon.appendingPathComponent("icon.json"))
        let model = ConversionViewModel(externalToolsPermitted: true)
        model.importFiles([icon, icon])
        #expect(model.jobs.count == 1)
        #expect(model.selectedJob?.input.path == icon.path)
        #expect(!model.canConvert)
        model.removeSelected()
        #expect(model.jobs.isEmpty && model.selection == nil)
    }

    @Test func invalidImportsHaveUnderstandableErrors() {
        let model = ConversionViewModel(externalToolsPermitted: true)
        model.importFiles([URL(fileURLWithPath: "/tmp/not-an-icon.png")])
        #expect(model.jobs.isEmpty)
        #expect(model.message?.contains(".icon") == true)
    }

    @Test func sandboxedBuildDoesNotStartToolExecution() {
        let model = ConversionViewModel(externalToolsPermitted: false)
        model.refreshTools()
        #expect(model.tools == nil)
        #expect(model.toolIssue?.contains("App Sandbox") == true)
        #expect(!model.canConvert)
    }

    @Test func batchNamesDoNotCollideOnCaseInsensitiveVolumes() {
        let plan = BatchPlanner.plan(inputs: ["/one/App.icon", "/two/app.icon", "/three/APP.icon"].map { URL(fileURLWithPath: $0) }, folder: URL(fileURLWithPath: "/tmp/Export"))
        #expect(plan.map { $0.output.lastPathComponent } == ["App.icns", "app (2).icns", "APP (3).icns"])
    }
}
