import Foundation
import IconConversionCore
import Testing
@testable import IconMatorPresentation

@MainActor struct WelcomeTests {
    private let macOS27 = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)

    @Test func welcomeAppearsOnlyUntilThisVersionIsCompleted() throws {
        let suite = "IconMator-WelcomeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(WelcomeProgress.shouldPresent(completedVersion: defaults.integer(forKey: WelcomeProgress.completionKey)))
        defaults.set(WelcomeProgress.currentVersion, forKey: WelcomeProgress.completionKey)
        #expect(!WelcomeProgress.shouldPresent(completedVersion: defaults.integer(forKey: WelcomeProgress.completionKey)))
        #expect(!WelcomeProgress.shouldPresent(completedVersion: WelcomeProgress.currentVersion + 1))
        #expect(WelcomePage.allCases == [.introduction, .environment])
    }

    @Test func reportUsesActualSDKAndAllSixCapabilities() {
        let report = WelcomeEnvironmentReport(tools: fixtureTools(), isChecking: false, issue: nil, systemVersion: macOS27)
        #expect(report.readiness == .ready)
        #expect(report.requirements.allSatisfy { $0.state == .passed })
        #expect(report.requirements.first { $0.id == .sdk }?.detail.contains("27.0") == true)
        #expect(report.requirements.first { $0.id == .composer }?.detail.contains("129") == true)
        #expect(report.issue == nil)
    }

    @Test func missingComposerIsLimitedOnlyOnMacOS27() {
        let tools = fixtureTools(composer: false)
        let report = WelcomeEnvironmentReport(tools: tools, isChecking: false, issue: nil, systemVersion: macOS27)
        #expect(report.readiness == .limited)
        #expect(report.requirements.first { $0.id == .composer }?.state == .limited)
        #expect(report.issue?.contains("Icon Composer") == true)

        let olderHost = WelcomeEnvironmentReport(tools: fixtureTools(composer: false, host: "26.6 (fixture)"),
            isChecking: false, issue: nil, systemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0))
        #expect(olderHost.readiness == .unavailable)
        #expect(olderHost.requirements.first { $0.id == .composer }?.state == .failed)
    }

    @Test func unsupportedSDKDoesNotClaimDefaultRenderingIsAvailable() {
        let report = WelcomeEnvironmentReport(tools: fixtureTools(sdk: "26.4", composer: false),
            isChecking: false, issue: "Unsupported SDK", systemVersion: macOS27)
        #expect(report.readiness == .unavailable)
        #expect(report.requirements.first { $0.id == .xcode }?.state == .passed)
        #expect(report.requirements.first { $0.id == .sdk }?.state == .failed)
        #expect(report.requirements.first { $0.id == .sdk }?.detail.contains("26.4") == true)
        #expect(report.requirements.first { $0.id == .composer }?.state == .notChecked)
    }

    @Test func checkingAndMissingToolsNeverShowSuccess() {
        let checking = WelcomeEnvironmentReport(tools: nil, isChecking: true, issue: nil, systemVersion: macOS27)
        #expect(checking.readiness == .checking)
        #expect(checking.requirements.filter { $0.state == .checking }.count == 3)
        let failed = WelcomeEnvironmentReport(tools: nil, isChecking: false, issue: "Select a full Xcode installation.", systemVersion: macOS27)
        #expect(failed.readiness == .unavailable)
        #expect(failed.requirements.first { $0.id == .xcode }?.state == .failed)
        #expect(failed.requirements.first { $0.id == .sdk }?.state == .notChecked)
    }

    @Test func missingGenerationInterfaceIsReportedAsPartialSupport() {
        let report = WelcomeEnvironmentReport(tools: fixtureTools(generationSelection: false), isChecking: false, issue: nil, systemVersion: macOS27)
        #expect(report.readiness == .limited)
        #expect(report.issue?.contains("--design-generation") == true)
    }

    @Test func failedSDKCheckRetainsDetectedVersionsAndRecheckCanRecover() async throws {
        let sequence = ToolSequence([fixtureTools(sdk: "26.4"), fixtureTools()])
        let model = ConversionViewModel(externalToolsPermitted: true, toolLocator: { await sequence.next() })
        model.refreshTools()
        // A second refresh during the first must not start a concurrent check.
        model.refreshTools()
        await waitForCheck(model)
        #expect(model.tools == nil)
        #expect(model.detectedTools?.sdkVersion == "26.4")
        #expect(model.toolIssue != nil)
        #expect(!model.canConvert)
        #expect(await sequence.callCount == 1)
        model.refreshTools()
        await waitForCheck(model)
        #expect(model.tools?.sdkVersion == "27.0")
        #expect(model.detectedTools?.sdkVersion == "27.0")
        #expect(model.toolIssue == nil)
        #expect(await sequence.callCount == 2)
        model.stopAllTasks()
    }

    private func waitForCheck(_ model: ConversionViewModel) async {
        for _ in 0..<400 where model.isCheckingTools { await Task.yield() }
        #expect(!model.isCheckingTools)
    }

    private func fixtureTools(sdk: String = "27.0", composer: Bool = true,
                              generationSelection: Bool = true, host: String = "27.0.1 (fixture)") -> DeveloperTools {
        DeveloperTools(developerDirectory: URL(fileURLWithPath: "/fixture/Xcode/Contents/Developer"),
            xcodebuild: URL(fileURLWithPath: "/fixture/xcodebuild"), actool: URL(fileURLWithPath: "/fixture/actool"),
            clang: URL(fileURLWithPath: "/fixture/clang"), sdk: URL(fileURLWithPath: "/fixture/SDK"), sdkVersion: sdk,
            iconutil: URL(fileURLWithPath: "/usr/bin/iconutil"), composerTool: composer ? URL(fileURLWithPath: "/usr/bin/true") : nil,
            composerInfo: composer ? ComposerToolInfo(path: "/usr/bin/true", shortVersion: "27.1", buildVersion: "129",
                interface: ComposerInterfaceCapabilities(exportImage: true, rendition: true, designGeneration: generationSelection)) : nil,
            xcodeVersion: "Xcode 27.1\nBuild version fixture", operatingSystem: host)
    }
}

private actor ToolSequence {
    private var tools: [DeveloperTools]
    private(set) var callCount = 0
    init(_ tools: [DeveloperTools]) { self.tools = tools }
    func next() -> DeveloperTools {
        callCount += 1
        return tools.removeFirst()
    }
}
