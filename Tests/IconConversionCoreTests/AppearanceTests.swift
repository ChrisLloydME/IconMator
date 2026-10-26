import Foundation
import Testing
@testable import IconConversionCore

private actor BackendLog {
    private var calls: [(backend: String, appearance: IconAppearance)] = []

    func record(_ backend: String, _ appearance: IconAppearance) {
        calls.append((backend, appearance))
    }

    func entries() -> [(backend: String, appearance: IconAppearance)] { calls }
}

private struct RecordingBackend: IconRenderingBackend {
    let name: String
    let log: BackendLog

    func render(input: URL, appearance: IconAppearance, workspace: URL, tools: DeveloperTools) async throws -> RenderedIcon {
        await log.record(name, appearance)
        return RenderedIcon(iconset: workspace.appendingPathComponent("rendered.iconset"),
            masterPNG: workspace.appendingPathComponent("rendered.iconset/icon_512x512@2x.png"),
            diagnostics: name, appearance: appearance, rendition: appearance.composerRendition?.rawValue ?? "",
            backend: name)
    }
}

private struct VersionRunner: ProcessRunning {
    let output: String
    func run(executable: URL, arguments: [String], directory: URL?, environment: [String: String]?) async throws -> ProcessOutput {
        ProcessOutput(output: output, status: 0)
    }
}

private func fixtureTools(composer: URL?) -> DeveloperTools {
    DeveloperTools(developerDirectory: URL(fileURLWithPath: "/fixture/Xcode/Contents/Developer"),
        xcodebuild: URL(fileURLWithPath: "/fixture/xcodebuild"),
        actool: URL(fileURLWithPath: "/fixture/actool"),
        clang: URL(fileURLWithPath: "/fixture/clang"),
        sdk: URL(fileURLWithPath: "/fixture/SDK"), sdkVersion: "27.0",
        iconutil: URL(fileURLWithPath: "/usr/bin/iconutil"),
        composerTool: composer,
        xcodeVersion: "Xcode 27.1\nBuild version 27A9275\n",
        operatingSystem: "27.0.1 (26A434)")
}

struct AppearanceTests {
    @Test func appearancesUseTheVerifiedRenditions() {
        #expect(IconAppearance.allCases == [.default, .dark, .mono])
        #expect(IconAppearance.default.rawValue == "default")
        #expect(IconAppearance.default.composerRendition == .default)
        #expect(IconAppearance.dark.composerRendition == .dark)
        #expect(IconAppearance.mono.composerRendition == .clearLight)
        #expect(IconAppearance.mono.displayName == "Mono")
    }

    @Test func omittedAppearancePreservesDefault() throws {
        let command = try CommandLineOptions.parseConvert(["convert", "input.icon", "output.icns"])
        #expect(command.appearance == .default)
        #expect(!command.exportPNG && !command.overwrite && !command.diagnostics)
    }

    @Test func cliParsesAppearancesAndPreservesExistingFlags() throws {
        let dark = try CommandLineOptions.parseConvert(["convert", "in.icon", "out.icns", "--appearance", "dark", "--png", "--replace", "--diagnostics"])
        #expect(dark.appearance == .dark)
        #expect(dark.exportPNG && dark.overwrite && dark.diagnostics)
        let mono = try CommandLineOptions.parseConvert(["convert", "in.icon", "out.icns", "--replace", "--appearance", "mono"])
        #expect(mono.appearance == .mono)
        #expect(mono.overwrite)
        #expect(!mono.exportPNG)
    }

    @Test func cliRejectsMalformedAppearanceArguments() {
        let missing = ["convert", "in.icon", "out.icns", "--appearance"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(missing) }
        let missingBeforeFlag = ["convert", "in.icon", "out.icns", "--appearance", "--png"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(missingBeforeFlag) }
        let invalid = ["convert", "in.icon", "out.icns", "--appearance", "clear"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(invalid) }
        let duplicate = ["convert", "in.icon", "out.icns", "--appearance", "dark", "--appearance", "mono"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(duplicate) }
        let unknown = ["convert", "in.icon", "out.icns", "--bogus"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(unknown) }
        let equalsForm = ["convert", "in.icon", "out.icns", "--appearance=dark"]
        #expect(throws: ConversionError.self) { try CommandLineOptions.parseConvert(equalsForm) }
    }

    @Test func packagePNGDoesNotAcceptAppearance() {
        #expect(throws: ConversionError.self) {
            try CommandLineOptions.parsePackagePNG(["package-png", "master.png", "out.icns", "--appearance", "dark"])
        }
        let package = try? CommandLineOptions.parsePackagePNG(["package-png", "master.png", "out.icns", "--replace"])
        #expect(package?.overwrite == true)
    }

    @Test func routerSelectsTheIntendedBackendAndNeverFallsBack() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let log = BackendLog()
        let router = IconRenderingRouter(compiled: RecordingBackend(name: "compiled", log: log),
                                         composer: RecordingBackend(name: "composer", log: log))
        let withComposer = fixtureTools(composer: URL(fileURLWithPath: "/fixture/ictool"))
        for appearance in IconAppearance.allCases {
            let rendered = try await router.render(input: workspace.url.appendingPathComponent("input.icon"),
                appearance: appearance, workspace: workspace.url, tools: withComposer)
            #expect(rendered.appearance == appearance)
        }
        let entries = await log.entries()
        #expect(entries.map(\.backend) == ["compiled", "composer", "composer"])
        #expect(entries.map(\.appearance) == [.default, .dark, .mono])

        // Missing Composer must fail the appearances that need it, while Default remains available.
        let withoutComposer = fixtureTools(composer: nil)
        await #expect(throws: ConversionError.self) {
            try await router.render(input: workspace.url.appendingPathComponent("input.icon"),
                appearance: .dark, workspace: workspace.url, tools: withoutComposer)
        }
        let defaultRendered = try await router.render(input: workspace.url.appendingPathComponent("input.icon"),
            appearance: .default, workspace: workspace.url, tools: withoutComposer)
        #expect(defaultRendered.appearance == .default)
    }

    @Test func missingComposerVersionIsReportedWithoutDisablingDefault() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        let executable = workspace.url.appendingPathComponent("ictool")
        #expect(FileManager.default.createFile(atPath: executable.path, contents: Data(), attributes: [.posixPermissions: 0o700]))
        let tools = fixtureTools(composer: executable)
        let capabilities = await AppearanceCapabilities.probe(tools: tools,
            runner: VersionRunner(output: "{\"bundle-version\":\"129\",\"short-bundle-version\":\"27.1\"}\n"))
        #expect(capabilities.composerTool?.displayVersion == "27.1 (129)")
        #expect(capabilities.capability(for: .default)?.isSupported == true)
        #expect(capabilities.capability(for: .dark)?.isSupported == true)
        #expect(capabilities.capability(for: .dark)?.rendition == "Dark")
        #expect(capabilities.capability(for: .mono)?.rendition == "ClearLight")

        let missing = await AppearanceCapabilities.probe(tools: fixtureTools(composer: nil), runner: VersionRunner(output: ""))
        #expect(missing.capability(for: .default)?.isSupported == true)
        #expect(missing.capability(for: .dark)?.isSupported == false)
        #expect(missing.capability(for: .mono)?.isSupported == false)
        #expect(missing.capability(for: .dark)?.reason?.contains("Icon Composer") == true)
    }

    @Test func composerBackendRequiresAVerifiableTool() async throws {
        let workspace = try TemporaryWorkspace(); defer { workspace.cleanUp() }
        await #expect(throws: ConversionError.self) {
            try await ComposerRenderingBackend().render(input: workspace.url.appendingPathComponent("input.icon"),
                appearance: .dark, workspace: workspace.url, tools: fixtureTools(composer: nil))
        }
    }
}
