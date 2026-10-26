import Foundation
import Testing
@testable import IconConversionCore

struct EngineTests {
    @Test func temporaryWorkspacesAreIsolatedAndCleaned() throws {
        let a = try TemporaryWorkspace(), b = try TemporaryWorkspace()
        #expect(a.url != b.url)
        try Data("A".utf8).write(to: a.url.appendingPathComponent("same-name"))
        try Data("B".utf8).write(to: b.url.appendingPathComponent("same-name"))
        a.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: a.url.path))
        #expect(FileManager.default.fileExists(atPath: b.url.path))
        b.cleanUp()
    }

    @Test func invalidInputAndSymlinksAreRejected() throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let icon = workspace.url.appendingPathComponent("空 格;$(invalid).icon")
        try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: false)
        #expect(throws: ConversionError.self) { try IconConversionService.validateInput(icon) }
        try Data("{\"groups\":[]}".utf8).write(to: icon.appendingPathComponent("icon.json"))
        try IconConversionService.validateInput(icon)
        try FileManager.default.createSymbolicLink(at: icon.appendingPathComponent("link"), withDestinationURL: icon.appendingPathComponent("icon.json"))
        #expect(throws: ConversionError.self) { try IconConversionService.validateInput(icon) }
    }

    @Test func atomicPublisherRefusesCollisionAndSupportsApprovedReplacement() throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let source = workspace.url.appendingPathComponent("source"), output = workspace.url.appendingPathComponent("out.icns")
        try Data("new".utf8).write(to: source)
        try Data("original".utf8).write(to: output)
        #expect(throws: ConversionError.self) { try OutputPublisher.publish(files: [(source, output)], overwrite: false) }
        #expect(try String(contentsOf: output, encoding: .utf8) == "original")
        try OutputPublisher.publish(files: [(source, output)], overwrite: true)
        #expect(try String(contentsOf: output, encoding: .utf8) == "new")
        let names = try FileManager.default.contentsOfDirectory(atPath: workspace.url.path)
        #expect(!names.contains(where: { $0.hasPrefix("IconMator-") }))
    }

    @Test func publisherPreparesAllOutputsBeforeChangingAny() throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let source = workspace.url.appendingPathComponent("source"), output = workspace.url.appendingPathComponent("out.icns")
        try Data("new".utf8).write(to: source)
        try Data("original".utf8).write(to: output)
        #expect(throws: (any Error).self) {
            try OutputPublisher.publish(files: [(source, output), (workspace.url.appendingPathComponent("missing"), workspace.url.appendingPathComponent("out.png"))], overwrite: true)
        }
        #expect(try String(contentsOf: output, encoding: .utf8) == "original")
    }

    @Test func processArgumentsAreNotInterpretedByShell() async throws {
        let argument = "路径 with spaces; $(touch INJECTION) `echo wrong`"
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", argument])
        #expect(result.output == argument)
    }

    @Test func processDiagnosticsAndFailureArePropagated() async throws {
        do {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
            Issue.record("Expected nonzero exit")
        } catch let error as ConversionError {
            guard case .processFailed(_, let status, _) = error else { Issue.record("Incorrect error category"); return }
            #expect(status != 0)
        }
    }

    @Test func processCanBeCancelled() async throws {
        let task = Task { try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func processTimeoutTerminatesTool() async throws {
        await #expect(throws: ConversionError.self) {
            try await ProcessRunner(timeout: 0.05).run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        }
    }

    @Test func unsupportedOrMissingToolchainFailsClearly() throws {
        let missing = DeveloperTools(developerDirectory: URL(fileURLWithPath: "/missing-xcode"), xcodebuild: URL(fileURLWithPath: "/missing-build"),
            actool: URL(fileURLWithPath: "/missing-actool"), clang: URL(fileURLWithPath: "/missing-clang"), sdk: URL(fileURLWithPath: "/missing-sdk"), sdkVersion: "26.0", iconutil: URL(fileURLWithPath: "/usr/bin/iconutil"),
            composerTool: nil, xcodeVersion: "Xcode 26", operatingSystem: "26.0")
        #expect(throws: ConversionError.self) { try missing.validatePinnedTools() }
        #expect(throws: ConversionError.self) { try missing.requireSupportedSDK() }
    }

    @Test func smallMasterIsNeverUpscaled() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let source = workspace.url.appendingPathComponent("small.png")
        try RasterImage.writePNG(pixels: [0, 0, 0, 255], width: 1, height: 1, to: source)
        await #expect(throws: ConversionError.self) {
            try await ICNSBuilder().fromPNG(source, workspace: workspace.url, tool: URL(fileURLWithPath: "/usr/bin/iconutil"))
        }
    }
}
