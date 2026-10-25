import Foundation
import Testing
@testable import IconConversionCore

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ICONMATOR_INTEGRATION"] == "1"))
struct AppleIntegrationTests {
    @Test func installedToolsAndReferenceRoundTrip() async throws {
        let tools = try await DeveloperToolLocator().locate()
        try tools.requireResearchedEnvironment()
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let reference = root.appendingPathComponent("ReferenceInputs/Metadatics/Metadatics.png")
        let output = workspace.url.appendingPathComponent("参考 with spaces.icns")
        _ = try await IconConversionService().packagePNG(input: reference, destination: output)
        let decoded = try await ConversionValidator().decodeAndValidate(icns: output, workspace: workspace.url, tool: tools.iconutil)
        let original = try RasterImage(url: reference)
        let result = try RasterImage(url: decoded.appendingPathComponent("icon_512x512@2x.png"))
        #expect(original.pixels == result.pixels)
    }

    @Test func realRenderingBatchCancellationAndInputPreservation() async throws {
        let tools = try await DeveloperToolLocator().locate()
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let original = root.appendingPathComponent("ReferenceInputs/Metadatics/Metadatics.icon")
        let before = try packageData(original)
        let copied = workspace.url.appendingPathComponent("路径 with spaces ; $().icon")
        try FileManager.default.copyItem(at: original, to: copied)
        let service = IconConversionService()
        async let first = service.convert(input: copied, destination: workspace.url.appendingPathComponent("first.icns"), tools: tools, exportPNG: true)
        async let second = service.convert(input: copied, destination: workspace.url.appendingPathComponent("second.icns"), tools: tools)
        let (a, b) = try await (first, second)
        #expect(a.icns != b.icns)
        let image = try RasterImage(url: #require(a.png))
        #expect(image.width == 1024 && image.height == 1024)
        #expect(image.geometry.transparentPixels > 0)
        let comparison = try ImageComparison.compare(reference: root.appendingPathComponent("ReferenceInputs/Metadatics/Metadatics.png"), candidate: #require(a.png), outputDirectory: workspace.url.appendingPathComponent("comparison"))
        // Empirical bound for this exact source and researched environment, not a general fidelity claim.
        #expect(comparison.maximumChannelDifference <= 5)
        #expect(comparison.maximumAlphaDifference <= 1)
        #expect(comparison.rgbaMeanAbsoluteError <= 0.15)
        #expect(comparison.reference.solidBounds == comparison.candidate.solidBounds)
        #expect(try packageData(original) == before)
        #expect(try packageData(copied) == before)
        let cancelled = workspace.url.appendingPathComponent("cancelled.icns")
        let task = Task { try await service.convert(input: copied, destination: cancelled, tools: tools) { stage in
            if stage == .rendering { try? await Task.sleep(for: .seconds(1)) }
        } }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: cancelled.path))
    }

    private func packageData(_ directory: URL) throws -> [String: Data] {
        let directory = directory.resolvingSymlinksInPath()
        var files: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            files[String(url.resolvingSymlinksInPath().path.dropFirst(directory.path.count))] = try Data(contentsOf: url)
        }
        return files
    }
}
