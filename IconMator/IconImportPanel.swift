import AppKit
import IconConversionCore

/// Icon Composer documents are directory packages. Do not depend on the machine's
/// extension-to-UTType registration to decide whether the Open panel can select them.
@MainActor final class IconImportPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    static func configure(_ panel: NSOpenPanel) {
        panel.title = "Import Icon Composer files"
        panel.prompt = "Import"
        panel.message = "Choose .icon files created with Icon Composer."
        panel.allowedContentTypes = []
        panel.treatsFilePackagesAsDirectories = false
        // Set these after content types/package behavior: macOS 27 can reset them.
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false }
        // Ordinary directories must remain navigable. Only .icon packages are importable.
        if values.isDirectory == true, values.isPackage != true { return true }
        return values.isDirectory == true && url.pathExtension.lowercased() == "icon"
    }

    func panel(_ sender: Any, validate url: URL) throws {
        try IconConversionService.validateInput(url)
    }
}
