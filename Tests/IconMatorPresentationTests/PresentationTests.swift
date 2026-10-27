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
        let plan = BatchPlanner.plan(inputs: ["/one/App.icon", "/two/app.icon", "/three/APP.icon"].map { URL(fileURLWithPath: $0) }, folder: URL(fileURLWithPath: "/tmp/Export"), options: .defaultOptions)
        #expect(plan.map { $0.output.lastPathComponent } == ["App-macOS-27-Default.icns", "app-macOS-27-Default (2).icns", "APP-macOS-27-Default (3).icns"])
    }

    @Test func exportNamesIncludeSelectedGenerationAndAppearance() {
        let input = URL(fileURLWithPath: "/tmp/应用 Icon.v2.icon")
        let folder = URL(fileURLWithPath: "/tmp/Export")
        var names = Set<String>()
        for generation in IconDesignGeneration.allCases {
            for appearance in IconAppearance.allCases {
                let options = IconRenderOptions(generation: generation, appearance: appearance)
                let plan = BatchPlanner.plan(inputs: [input], folder: folder, options: options)
                let expected = "应用 Icon.v2-macOS-\(generation.rawValue)-\(appearance.displayName)"
                #expect(plan.count == 1)
                #expect(plan[0].input == input)
                #expect(plan[0].output == folder.appendingPathComponent(expected + ".icns"))
                #expect(plan[0].output.deletingPathExtension().appendingPathExtension("png").lastPathComponent == expected + ".png")
                names.insert(plan[0].output.lastPathComponent)
            }
        }
        #expect(names.count == 6)
    }
}
