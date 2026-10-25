import Foundation
import Testing
@testable import IconConversionCore

private struct DiscoveryRunner: ProcessRunning {
    let developer: URL
    func run(executable: URL, arguments: [String], directory: URL?, environment: [String: String]?) async throws -> ProcessOutput {
        let output: String
        switch executable.lastPathComponent {
        case "xcode-select": output = developer.path
        case "xcrun":
            guard environment?["DEVELOPER_DIR"] == developer.path else { throw ConversionError.validation("Tool selection was not pinned") }
            output = arguments.first == "--find" ? developer.appendingPathComponent("usr/bin/\(arguments.last!)").path : developer.appendingPathComponent("SDKs/Test.sdk").path
        case "xcodebuild": output = "Xcode 27.1\nBuild version 27A9275\n"
        case "sw_vers": output = arguments == ["-productVersion"] ? "27.0.1" : "26A434"
        default: throw ConversionError.missingTool("Unexpected discovery invocation")
        }
        return ProcessOutput(output: output + "\n", status: 0)
    }
}

struct ToolDiscoveryTests {
    // Mock only discovery commands, never renderer behavior or integration results.
    @Test(arguments: [false, true]) func discoversRelocatedXcodeAndHonorsAppOverride(useOverride: Bool) async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let app = workspace.url.appendingPathComponent("开发 Tools/Xcode Custom.app")
        let developer = app.appendingPathComponent("Contents/Developer")
        let bins = developer.appendingPathComponent("usr/bin")
        try FileManager.default.createDirectory(at: bins, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: developer.appendingPathComponent("SDKs/Test.sdk"), withIntermediateDirectories: true)
        for name in ["xcodebuild", "actool", "clang"] {
            #expect(FileManager.default.createFile(atPath: bins.appendingPathComponent(name).path, contents: Data(), attributes: [.posixPermissions: 0o700]))
        }
        let tools = try await DeveloperToolLocator(runner: DiscoveryRunner(developer: developer), environment: useOverride ? ["DEVELOPER_DIR": app.path] : [:]).locate()
        #expect(tools.developerDirectory.path == developer.path)
        #expect(tools.actool.path == bins.appendingPathComponent("actool").path)
        #expect(tools.composerTool == nil)
        try tools.requireResearchedEnvironment()
    }

    @Test func commandLineToolsDirectoryIsNotAcceptedAsFullXcode() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        await #expect(throws: ConversionError.self) {
            try await DeveloperToolLocator(runner: DiscoveryRunner(developer: workspace.url), environment: [:]).locate()
        }
    }
}
