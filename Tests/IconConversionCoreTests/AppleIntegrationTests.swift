import Foundation
import Testing
@testable import IconConversionCore

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ICONMATOR_INTEGRATION"] == "1"))
struct AppleIntegrationTests {
    @Test func installedToolsAndReferenceRoundTrip() async throws {
        let tools = try await DeveloperToolLocator().locate()
        try tools.requireSupportedSDK()
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
        #expect(a.options == IconRenderOptions(generation: .macOS27, appearance: .default))
        #expect(a.backend == RenderCapabilities.compiledBackendName)
        #expect(a.composerVersion == nil)
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
        let task = Task { try await service.convert(input: copied, destination: cancelled, tools: tools,
            options: IconRenderOptions(generation: .macOS26, appearance: .default)) { stage in
            if stage == .rendering { try? await Task.sleep(for: .seconds(1)) }
        } }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: cancelled.path))
    }

    @Test func renderGenerationMatrixPreservesCanvasPackagingAndInputs() async throws {
        let tools = try await DeveloperToolLocator().locate()
        try tools.requireSupportedSDK()
        _ = try #require(tools.composerTool)
        #expect(try #require(tools.composerInfo).supportsGenerationSelection)
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
        var rendered: [String: [IconRenderOptions: RasterImage]] = [:]
        var sawGenerationDifference = false
        var sawAppearanceDifference = false
        for (name, source) in sources {
            let before = try packageData(source)
            for generation in IconDesignGeneration.allCases {
                for appearance in IconAppearance.allCases {
                    let options = IconRenderOptions(generation: generation, appearance: appearance)
                    let destination = workspace.url.appendingPathComponent("\(name)-\(generation.rawValue)-\(appearance.rawValue).icns")
                    let result = try await service.convert(input: source, destination: destination, tools: tools,
                        options: options, exportPNG: true)
                    #expect(result.options == options)
                    #expect(result.generation == generation)
                    #expect(result.appearance == appearance)
                    #expect(result.rendition == appearance.composerRendition?.rawValue)
                    if options == .defaultOptions {
                        #expect(result.backend == RenderCapabilities.compiledBackendName)
                        #expect(result.composerVersion == nil)
                    } else {
                        #expect(result.backend == RenderCapabilities.composerBackendName)
                        #expect(result.composerVersion == tools.composerInfo?.displayVersion)
                    }

                    let png = try #require(result.png)
                    let image = try RasterImage(url: png)
                    #expect(image.width == 1024 && image.height == 1024)
                    #expect(image.geometry.sourceHasAlpha)
                    #expect(image.geometry.transparentPixels > 0)
                    #expect(image.geometry.visibleBounds != nil)
                    #expect(image.geometry.solidBounds == PixelBounds(x: 100, y: 100, width: 824, height: 824))
                    rendered[name, default: [:]][options] = image

                    let decoded = try await ConversionValidator().decodeAndValidate(icns: destination, workspace: workspace.url, tool: tools.iconutil)
                    let decodedMaster = try RasterImage(url: decoded.appendingPathComponent("icon_512x512@2x.png"))
                    #expect(decodedMaster.pixels == image.pixels)
                    let names = try FileManager.default.contentsOfDirectory(atPath: decoded.path)
                    for representation in IconRepresentation.standard {
                        #expect(names.contains(representation.name))
                    }
                }
            }
            #expect(try packageData(source) == before)
        }

        for images in rendered.values {
            let default26 = images[IconRenderOptions(generation: .macOS26, appearance: .default)]
            let default27 = images[IconRenderOptions(generation: .macOS27, appearance: .default)]
            if let default26, let default27, default26.pixels != default27.pixels { sawGenerationDifference = true }
            let dark26 = images[IconRenderOptions(generation: .macOS26, appearance: .dark)]
            if let dark26, let default26, dark26.pixels != default26.pixels { sawAppearanceDifference = true }
            let mono27 = images[IconRenderOptions(generation: .macOS27, appearance: .mono)]
            if let mono27, let default27, mono27.pixels != default27.pixels { sawAppearanceDifference = true }
        }
        #expect(sawGenerationDifference)
        #expect(sawAppearanceDifference)
    }

    @Test func directComposerGenerationsAreGenuinelyDifferent() async throws {
        let tools = try await DeveloperToolLocator().locate()
        let composer = try #require(tools.composerTool)
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let source = try makeSyntheticIcon(in: workspace.url)
        let snapshot = workspace.url.appendingPathComponent("Direct.icon")
        try FileManager.default.copyItem(at: source, to: snapshot)
        var images: [IconDesignGeneration: RasterImage] = [:]
        for generation in IconDesignGeneration.allCases {
            let output = workspace.url.appendingPathComponent("direct-\(generation.rawValue).png")
            let options = IconRenderOptions(generation: generation, appearance: .default)
            let arguments = try ComposerRenderingBackend.rendererArguments(input: snapshot, output: output, options: options)
            _ = try await ProcessRunner().run(executable: composer, arguments: arguments,
                directory: workspace.url, environment: tools.environment)
            let image = try RasterImage(url: output)
            #expect(image.width == 1024 && image.height == 1024)
            #expect(image.geometry.sourceHasAlpha)
            #expect(image.geometry.visibleBounds == PixelBounds(x: 0, y: 0, width: 1024, height: 1024))
            images[generation] = image
        }
        let first = try #require(images[.macOS26])
        let second = try #require(images[.macOS27])
        #expect(first.pixels != second.pixels)
        #expect(first.geometry.solidBounds == PixelBounds(x: 0, y: 0, width: 1024, height: 1024))
        #expect(second.geometry.solidBounds == PixelBounds(x: 0, y: 0, width: 1024, height: 1024))
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
