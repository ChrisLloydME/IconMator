import Foundation
import Testing
@testable import IconConversionCore

private actor BackendLog {
    private var calls: [(backend: String, options: IconRenderOptions)] = []

    func record(_ backend: String, _ options: IconRenderOptions) {
        calls.append((backend, options))
    }

    func entries() -> [(backend: String, options: IconRenderOptions)] { calls }
}

private struct RecordingBackend: IconRenderingBackend {
    let name: String
    let log: BackendLog

    func render(input: URL, options: IconRenderOptions, workspace: URL, tools: DeveloperTools) async throws -> RenderedIcon {
        await log.record(name, options)
        return RenderedIcon(iconset: workspace.appendingPathComponent("rendered.iconset"),
            masterPNG: workspace.appendingPathComponent("rendered.iconset/icon_512x512@2x.png"),
            diagnostics: name, options: options,
            rendition: options.appearance.composerRendition?.rawValue ?? "",
            backend: name, composerVersion: tools.composerInfo?.displayVersion)
    }
}

private struct ScriptedRunner: ProcessRunning {
    var version: String = "{\"bundle-version\":\"129\",\"short-bundle-version\":\"27.1\"}\n"
    var help: String? = ComposerInterfaceCapabilities.sampleHelp
    var versionFails = false
    var helpFails = false

    func run(executable: URL, arguments: [String], directory: URL?, environment: [String: String]?) async throws -> ProcessOutput {
        switch arguments {
        case ["--version"]:
            if versionFails { throw ConversionError.processFailed("ictool", 1, "version failed") }
            return ProcessOutput(output: version, status: 0)
        case ["--help"]:
            if helpFails { throw ConversionError.processFailed("ictool", 1, "help failed") }
            return ProcessOutput(output: help ?? "", status: 0)
        default:
            throw ConversionError.validation("Unexpected renderer inspection arguments: \(arguments)")
        }
    }
}

private extension ComposerInterfaceCapabilities {
    static let sampleHelp = """
    ictool processes Icon Composer documents
    Usage:
        ictool input-document --export-image --output-file <path> --platform <platform>
          --rendition <rendition> --width <width> --height <height> --scale <scale>
          [--design-generation <26 or 27>]
    """
}

private let supportedInterface = ComposerInterfaceCapabilities(exportImage: true, rendition: true, designGeneration: true)

private func composerInfo(shortVersion: String? = "27.1", buildVersion: String? = "129",
                          interface: ComposerInterfaceCapabilities? = supportedInterface) -> ComposerToolInfo {
    ComposerToolInfo(path: "/usr/bin/true", shortVersion: shortVersion, buildVersion: buildVersion, interface: interface)
}

private func fixtureTools(composer: Bool, host: String = "27.0.1 (26A434)",
                          info: ComposerToolInfo? = nil,
                          issue: String? = nil) -> DeveloperTools {
    DeveloperTools(developerDirectory: URL(fileURLWithPath: "/fixture/Xcode/Contents/Developer"),
        xcodebuild: URL(fileURLWithPath: "/fixture/xcodebuild"),
        actool: URL(fileURLWithPath: "/fixture/actool"),
        clang: URL(fileURLWithPath: "/fixture/clang"),
        sdk: URL(fileURLWithPath: "/fixture/SDK"), sdkVersion: "27.0",
        iconutil: URL(fileURLWithPath: "/usr/bin/iconutil"),
        composerTool: composer ? URL(fileURLWithPath: "/usr/bin/true") : nil,
        composerInfo: composer ? (info ?? composerInfo()) : nil,
        composerIssue: composer ? issue : nil,
        xcodeVersion: "Xcode 27.1\nBuild version 27A9275\n",
        operatingSystem: host)
}

struct RenderingOptionsTests {
    @Test func generationValuesAndDefaultsAreStable() {
        #expect(IconDesignGeneration.allCases == [.macOS26, .macOS27])
        #expect(IconDesignGeneration.macOS26.rawValue == 26)
        #expect(IconDesignGeneration.macOS27.rawValue == 27)
        #expect(IconDesignGeneration.macOS26.displayName == "macOS 26")
        #expect(IconDesignGeneration(cliValue: "26") == .macOS26)
        #expect(IconDesignGeneration(cliValue: "27") == .macOS27)
        #expect(IconDesignGeneration(cliValue: "25") == nil)
        #expect(IconDesignGeneration(cliValue: "27.0") == nil)
        #expect(IconRenderOptions.defaultOptions == IconRenderOptions(generation: .macOS27, appearance: .default))
        #expect(IconRenderOptions.defaultOptions.displayName == "macOS 27 · Default")
    }

    @Test func appearancesUseTheVerifiedRenditions() {
        #expect(IconAppearance.allCases == [.default, .dark, .mono])
        #expect(IconAppearance.default.rawValue == "default")
        #expect(IconAppearance.default.composerRendition == .default)
        #expect(IconAppearance.dark.composerRendition == .dark)
        #expect(IconAppearance.mono.composerRendition == .clearLight)
        #expect(IconAppearance.mono.displayName == "Mono")
    }

    @Test func omittedGenerationAndAppearancePreserveDefaults() throws {
        let command = try CommandLineOptions.parseConvert(["convert", "input.icon", "output.icns"])
        #expect(command.generation == .macOS27)
        #expect(command.appearance == .default)
        #expect(command.options == .defaultOptions)
        #expect(!command.exportPNG && !command.overwrite && !command.diagnostics)
    }

    @Test func cliParsesAllSixGenerationAppearanceCombinations() throws {
        for generation in IconDesignGeneration.allCases {
            for appearance in IconAppearance.allCases {
                let command = try CommandLineOptions.parseConvert(["convert", "in.icon", "out.icns",
                    "--generation", generation.cliValue, "--appearance", appearance.rawValue,
                    "--png", "--replace", "--diagnostics"])
                #expect(command.options == IconRenderOptions(generation: generation, appearance: appearance))
                #expect(command.exportPNG && command.overwrite && command.diagnostics)
            }
        }
    }

    @Test func cliRejectsMalformedGenerationArguments() {
        let missing = ["convert", "in.icon", "out.icns", "--generation"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(missing) }
        let missingBeforeFlag = ["convert", "in.icon", "out.icns", "--generation", "--png"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(missingBeforeFlag) }
        for invalid in ["25", "28", "27.0", "26.1", "macOS26", "beta", "026", "+26", " 26"] {
            #expect(throws: ConversionError.self) {
                try CommandLineOptions.parseConvert(["convert", "in.icon", "out.icns", "--generation", invalid])
            }
        }
        let duplicate = ["convert", "in.icon", "out.icns", "--generation", "26", "--generation", "27"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(duplicate) }
        let unknown = ["convert", "in.icon", "out.icns", "--bogus"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(unknown) }
        let equalsForm = ["convert", "in.icon", "out.icns", "--generation=26"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(equalsForm) }
    }

    @Test func packagePNGDoesNotAcceptRenderingOptions() {
        #expect(throws: ConversionError.self) {
            try CommandLineOptions.parsePackagePNG(["package-png", "master.png", "out.icns", "--appearance", "dark"])
        }
        #expect(throws: ConversionError.self) {
            try CommandLineOptions.parsePackagePNG(["package-png", "master.png", "out.icns", "--generation", "26"])
        }
        #expect(throws: ConversionError.self) {
            try CommandLineOptions.parsePackagePNG(["package-png", "master.png", "out.icns", "--generation=26"])
        }
        let package = try? CommandLineOptions.parsePackagePNG(["package-png", "master.png", "out.icns", "--replace"])
        #expect(package?.overwrite == true)
    }

    @Test func composerInterfaceParserIsNarrowAndFormattingTolerant() {
        let quoted = ComposerInterfaceCapabilities.parse(help:
            "Usage: ictool --export-image --output-file out.png --rendition Dark --design-generation <26 or 27>")
        #expect(quoted.supportsRequiredArguments)
        let wrapped = ComposerInterfaceCapabilities.parse(help:
            "ictool input --export-image\n  --rendition\n  --design-generation 26")
        #expect(wrapped.supportsRequiredArguments)
        let missingGeneration = ComposerInterfaceCapabilities.parse(help:
            "ictool --export-image --rendition Default")
        #expect(missingGeneration.exportImage && missingGeneration.rendition)
        #expect(!missingGeneration.designGeneration)
        #expect(missingGeneration.missingOptions == ["--design-generation"])
        let longerName = ComposerInterfaceCapabilities.parse(help:
            "ictool --export-image --rendition --design-generations")
        #expect(!longerName.designGeneration)
        let embedded = ComposerInterfaceCapabilities.parse(help:
            "ictool --export-image --rendition prefix--design-generation")
        #expect(!embedded.designGeneration)
    }

    @Test func composerInspectionReadsVersionAndHelp() async throws {
        let tools = fixtureTools(composer: true)
        let info = try await ComposerToolInfo.load(tools: tools, runner: ScriptedRunner())
        #expect(info?.displayVersion == "27.1 (129)")
        #expect(info?.supportsGenerationSelection == true)

        let helpFailure = try await ComposerToolInfo.load(tools: tools, runner: ScriptedRunner(helpFails: true))
        #expect(helpFailure != nil)
        #expect(helpFailure?.interface == nil)
        #expect(helpFailure?.supportsGenerationSelection == false)

        let versionFailure = try await ComposerToolInfo.load(tools: tools, runner: ScriptedRunner(versionFails: true))
        #expect(versionFailure == nil)
    }

    @Test func routerCoversAllSixCombinations() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let log = BackendLog()
        let router = IconRenderingRouter(compiled: RecordingBackend(name: "compiled", log: log),
                                         composer: RecordingBackend(name: "composer", log: log))
        let tools = fixtureTools(composer: true)
        var expectedBackends: [String] = []
        for generation in IconDesignGeneration.allCases {
            for appearance in IconAppearance.allCases {
                let options = IconRenderOptions(generation: generation, appearance: appearance)
                let rendered = try await router.render(input: workspace.url.appendingPathComponent("input.icon"),
                    options: options, workspace: workspace.url, tools: tools)
                #expect(rendered.options == options)
                #expect(rendered.generation == generation)
                #expect(rendered.appearance == appearance)
                if generation == .macOS27, appearance == .default {
                    #expect(IconRenderingRouter.route(for: options, tools: tools) == .compiledDefault)
                    expectedBackends.append("compiled")
                } else {
                    #expect(IconRenderingRouter.route(for: options, tools: tools) == .composer)
                    expectedBackends.append("composer")
                }
            }
        }
        let entries = await log.entries()
        #expect(entries.map(\.backend) == expectedBackends)
        #expect(entries.map(\.options) == IconDesignGeneration.allCases.flatMap { generation in
            IconAppearance.allCases.map { IconRenderOptions(generation: generation, appearance: $0) }
        })
    }

    @Test func routerDoesNotAssumeUnknownOrFutureHostsMatchMacOS27() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let log = BackendLog()
        let router = IconRenderingRouter(compiled: RecordingBackend(name: "compiled", log: log),
                                         composer: RecordingBackend(name: "composer", log: log))
        for host in ["26.0.1 (25A1234)", "28.0 (28A1)", "fixture"] {
            let tools = fixtureTools(composer: true, host: host)
            let rendered = try await router.render(input: workspace.url.appendingPathComponent("input.icon"),
                options: .defaultOptions, workspace: workspace.url, tools: tools)
            #expect(rendered.backend == "composer")
        }
        let entries = await log.entries()
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.backend == "composer" })
    }

    @Test func missingComposerNeverFallsBackForGenerationOrAppearance() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let log = BackendLog()
        let router = IconRenderingRouter(compiled: RecordingBackend(name: "compiled", log: log),
                                         composer: RecordingBackend(name: "composer", log: log))
        let tools = fixtureTools(composer: false)
        let compiled = try await router.render(input: workspace.url.appendingPathComponent("input.icon"),
            options: .defaultOptions, workspace: workspace.url, tools: tools)
        #expect(compiled.backend == "compiled")
        for generation in IconDesignGeneration.allCases {
            for appearance in IconAppearance.allCases where !(generation == .macOS27 && appearance == .default) {
                await #expect(throws: ConversionError.self) {
                    try await router.render(input: workspace.url.appendingPathComponent("input.icon"),
                        options: IconRenderOptions(generation: generation, appearance: appearance),
                        workspace: workspace.url, tools: tools)
                }
            }
        }
        let entries = await log.entries()
        #expect(entries.map(\.backend) == ["compiled"])
    }

    @Test func compiledBackendRejectsGenerationsItCannotRepresent() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let backend = CompiledAssetBackend()
        for (options, host) in [
            (IconRenderOptions(generation: .macOS26, appearance: .default), "27.0.1 (26A434)"),
            (IconRenderOptions(generation: .macOS27, appearance: .default), "26.0.1 (25A1234)"),
            (IconRenderOptions(generation: .macOS27, appearance: .default), "fixture"),
            (IconRenderOptions(generation: .macOS27, appearance: .dark), "27.0.1 (26A434)")
        ] {
            let tools = fixtureTools(composer: true, host: host)
            await #expect(throws: ConversionError.self) {
                try await backend.render(input: workspace.url.appendingPathComponent("input.icon"),
                    options: options, workspace: workspace.url, tools: tools)
            }
        }
    }

    @Test func composerBackendRejectsMissingGenerationInterfaceBeforeRendering() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let backend = ComposerRenderingBackend(runner: ScriptedRunner())
        let noGeneration = ComposerInterfaceCapabilities(exportImage: true, rendition: true, designGeneration: false)
        for info in [composerInfo(interface: noGeneration), composerInfo(interface: nil)] {
            let tools = fixtureTools(composer: true, info: info)
            await #expect(throws: ConversionError.self) {
                try await backend.render(input: workspace.url.appendingPathComponent("input.icon"),
                    options: IconRenderOptions(generation: .macOS26, appearance: .default),
                    workspace: workspace.url, tools: tools)
            }
        }
    }

    @Test func capabilitiesDistinguishCompiledComposerAndGenerationSelection() {
        let supported = RenderCapabilities.probe(tools: fixtureTools(composer: true))
        #expect(supported.capabilities.count == 6)
        #expect(supported.capability(for: .defaultOptions)?.backend == RenderCapabilities.compiledBackendName)
        #expect(supported.capability(for: .defaultOptions)?.requiresComposer == false)
        #expect(IconDesignGeneration.allCases.flatMap { generation in
            IconAppearance.allCases.map { appearance in
                supported.capability(for: IconRenderOptions(generation: generation, appearance: appearance))?.isSupported == true
            }
        }.allSatisfy { $0 })
        #expect(supported.composerSupportsGenerationSelection)

        let missing = RenderCapabilities.probe(tools: fixtureTools(composer: false))
        #expect(missing.capability(for: .defaultOptions)?.isSupported == true)
        for generation in IconDesignGeneration.allCases {
            for appearance in IconAppearance.allCases where !(generation == .macOS27 && appearance == .default) {
                let capability = missing.capability(for: IconRenderOptions(generation: generation, appearance: appearance))
                #expect(capability?.isSupported == false)
                #expect(capability?.reason?.contains("Icon Composer") == true)
            }
        }

        let noSelection = RenderCapabilities.probe(tools: fixtureTools(composer: true,
            info: composerInfo(interface: ComposerInterfaceCapabilities(exportImage: true, rendition: true, designGeneration: false))))
        #expect(noSelection.capability(for: .defaultOptions)?.isSupported == true)
        let generation26 = noSelection.capability(for: IconRenderOptions(generation: .macOS26, appearance: .default))
        #expect(generation26?.isSupported == false)
        #expect(generation26?.reason?.contains("--design-generation") == true)
        #expect(noSelection.composerSupportsGenerationSelection == false)

        let otherHost = RenderCapabilities.probe(tools: fixtureTools(composer: true, host: "26.0.1 (25A1234)"))
        #expect(otherHost.capability(for: .defaultOptions)?.backend == RenderCapabilities.composerBackendName)
        #expect(otherHost.capabilities.allSatisfy { $0.isSupported })
    }

    @Test func toolIdentityIncludesComposerVersionAndInterface() {
        let first = fixtureTools(composer: true, info: composerInfo(shortVersion: "27.1", buildVersion: "129"))
        let second = fixtureTools(composer: true, info: composerInfo(shortVersion: "27.2", buildVersion: "130"))
        let noGeneration = fixtureTools(composer: true,
            info: composerInfo(interface: ComposerInterfaceCapabilities(exportImage: true, rendition: true, designGeneration: false)))
        #expect(first.identity != second.identity)
        #expect(first.identity != noGeneration.identity)
        #expect(RenderCapabilities.probe(tools: first).toolIdentity == first.identity)
        #expect(RenderCapabilities.probe(tools: first).toolIdentity != RenderCapabilities.probe(tools: second).toolIdentity)
    }

    @Test func rendererArgumentsIncludeExplicitGenerationAndRendition() throws {
        let input = URL(fileURLWithPath: "/tmp/Input.icon")
        let output = URL(fileURLWithPath: "/tmp/Output.png")
        for generation in IconDesignGeneration.allCases {
            for appearance in IconAppearance.allCases {
                let options = IconRenderOptions(generation: generation, appearance: appearance)
                let arguments = try ComposerRenderingBackend.rendererArguments(input: input, output: output, options: options)
                #expect(arguments.contains("--export-image"))
                #expect(arguments.contains("--rendition"))
                #expect(arguments[arguments.firstIndex(of: "--rendition")! + 1] == appearance.composerRendition?.rawValue)
                #expect(arguments.contains("--design-generation"))
                #expect(arguments[arguments.firstIndex(of: "--design-generation")! + 1] == String(generation.rawValue))
                #expect(arguments[arguments.firstIndex(of: "--width")! + 1] == "1024")
                #expect(arguments[arguments.firstIndex(of: "--height")! + 1] == "1024")
                #expect(arguments[arguments.firstIndex(of: "--platform")! + 1] == "macOS")
                #expect(arguments[0] == input.path)
                #expect(arguments[arguments.firstIndex(of: "--output-file")! + 1] == output.path)
            }
        }
    }
}
