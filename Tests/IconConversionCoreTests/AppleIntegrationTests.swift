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

    @Test func appearanceMatrixPreservesCanvasPackagingAndInputs() async throws {
        let tools = try await DeveloperToolLocator().locate()
        try tools.requireResearchedEnvironment()
        _ = try #require(tools.composerTool)
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let synthetic = try makeSyntheticIcon(in: workspace.url)
        var sources: [(String, URL)] = [
            ("AppIcon", root.appendingPathComponent("IconMator/AppIcon.icon")),
            ("Synthetic", synthetic)
        ]
        let metadatics = root.appendingPathComponent("ReferenceInputs/Metadatics/Metadatics.icon")
        if FileManager.default.fileExists(atPath: metadatics.path) { sources.append(("Metadatics", metadatics)) }

        let service = IconConversionService()
        var rendered: [String: [IconAppearance: RasterImage]] = [:]
        for (name, source) in sources {
            let before = try packageData(source)
            for appearance in IconAppearance.allCases {
                let destination = workspace.url.appendingPathComponent("\(name)-\(appearance.rawValue).icns")
                let result = try await service.convert(input: source, destination: destination, tools: tools,
                    appearance: appearance, exportPNG: true)
                #expect(result.appearance == appearance)
                #expect(result.rendition == appearance.composerRendition?.rawValue)
                if appearance != .default { #expect(result.backend.contains("Icon Composer")) }
                if appearance == .default { #expect(result.backend.contains("Compiled")) }

                let png = try #require(result.png)
                let image = try RasterImage(url: png)
                #expect(image.width == 1024 && image.height == 1024)
                #expect(image.geometry.sourceHasAlpha)
                #expect(image.geometry.transparentPixels > 0)
                #expect(image.geometry.visibleBounds != nil)
                #expect(image.geometry.solidBounds == PixelBounds(x: 100, y: 100, width: 824, height: 824))
                rendered[name, default: [:]][appearance] = image

                let decoded = try await ConversionValidator().decodeAndValidate(icns: destination, workspace: workspace.url, tool: tools.iconutil)
                let decodedMaster = try RasterImage(url: decoded.appendingPathComponent("icon_512x512@2x.png"))
                #expect(decodedMaster.pixels == image.pixels)
                let names = try FileManager.default.contentsOfDirectory(atPath: decoded.path)
                for representation in IconRepresentation.standard {
                    #expect(names.contains(representation.name))
                }
            }
            #expect(try packageData(source) == before)
        }

        // At least one source must expose a real appearance difference. Some icon
        // designs can legitimately produce identical Default/Dark results.
        var sawDifference = false
        for images in rendered.values {
            if let base = images[.default], let dark = images[.dark], base.pixels != dark.pixels { sawDifference = true }
            if let base = images[.default], let mono = images[.mono], base.pixels != mono.pixels { sawDifference = true }
        }
        #expect(sawDifference)

        // The appearance-specific path must clean up temporary output on cancellation too.
        let cancelled = workspace.url.appendingPathComponent("cancelled-dark.icns")
        let task = Task { try await service.convert(input: synthetic, destination: cancelled, tools: tools,
            appearance: .dark) { stage in
                if stage == .rendering { try? await Task.sleep(for: .seconds(1)) }
            } }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: cancelled.path))
    }

    private func makeSyntheticIcon(in parent: URL) throws -> URL {
        let icon = parent.appendingPathComponent("Synthetic.icon", isDirectory: true)
        let assets = icon.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        var pixels = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        let center = 512.0, radius = 290.0
        for y in 0..<1024 {
            for x in 0..<1024 {
                let dx = Double(x) - center, dy = Double(y) - center
                guard dx * dx + dy * dy <= radius * radius else { continue }
                let offset = (y * 1024 + x) * 4
                pixels[offset] = 235
                pixels[offset + 1] = 110
                pixels[offset + 2] = 45
                pixels[offset + 3] = 255
            }
        }
        try RasterImage.writePNG(pixels: pixels, width: 1024, height: 1024,
            to: assets.appendingPathComponent("Layer.png"))
        let document = """
        {
          "fill": { "automatic-gradient": "display-p3:0.10,0.30,0.55,1.0" },
          "groups": [{
            "name": "Test Group",
            "layers": [{ "image-name": "Layer.png", "name": "Test Layer",
              "position": { "scale": 1, "translation-in-points": [0, 0] } }],
            "position": { "scale": 1, "translation-in-points": [0, 0] },
            "shadow": { "kind": "neutral", "opacity": 0.5 },
            "translucency": { "enabled": true, "value": 0.3 }
          }],
          "supported-platforms": { "squares": ["macOS"] }
        }
        """
        try Data(document.utf8).write(to: icon.appendingPathComponent("icon.json"))
        return icon
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
