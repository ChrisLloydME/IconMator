# Architecture

IconMator consists of a Swift 6 package and the existing SwiftUI Xcode application. The app links the local `IconConversionCore` library; the `iconmator` executable exercises the same implementation without launching the UI. There are no third-party packages and no network calls in application code.

## Rendering pipeline

`IconConversionService` validates the input package, output location and selected developer environment. The source must be a readable directory with an `.icon` extension, valid `icon.json` and a `groups` array. Symbolic links inside the package are rejected. Output inside the input package is refused. Input files are never edited.

`DeveloperToolLocator` honors `DEVELOPER_DIR` (including an Xcode app URL), otherwise reads `xcode-select -p`. It resolves actool, clang and the SDK using xcrun, discovers the selected Xcode's bundled Composer executable, and records Xcode version/build and host version/build. It does not assume Xcode resides in `/Applications/Xcode.app`. Required executable paths are checked again before work; changes to the active selection or recorded versions cause an explicit failure. Conversion is restricted to the exact researched macOS/Xcode combination, rather than implying untested version compatibility.

`IconRenderingBackend` separates rendering from orchestration. The implemented `CompiledAssetBackend`:

1. Copies the input into a unique private temporary workspace as `AppIcon.icon`.
2. Invokes actool directly for macOS, deployment target 26.0, Default app icon, standalone behavior `all`.
3. Independently decodes the compiled ICNS and checks all required dimensions, alpha channels and nonempty content. Requires both the high-resolution compiled rendition and Assets.car.
4. Compiles our own minimal C stub using the selected clang and SDK. Creates a complete temporary `.app` with that executable and the compiled resources. Each bundle has a fresh URL and identifier; the app is **never launched**.
5. Uses public NSWorkspace under Aqua/Default appearance to obtain system-rendered images at each required size. Source images smaller than the request are rejected. The generic application icon is rejected. Equal-size 1×/2× slots share bytes.
6. Renders into sRGB with preserved alpha and explicit no-tone-mapping for extended-range HDR sources. It never synthesizes Liquid Glass, adds padding, clips artwork to a custom mask, creates shadows, or scales an already correct master to an assumed inner size.

System icon extraction runs on MainActor because it uses AppKit. Tool processes and expensive validation execute asynchronously outside the SwiftUI model. There is no automatic lower-fidelity rendering fallback.

`ICNSBuilder` packages the native requested representations. For the development-only PNG packaging command, it copies the genuine 1024² master unchanged and uses CoreGraphics high-quality interpolation separately from that master for smaller sizes. This path does not accept or upscale a low-resolution master.

`IconFamilyEncoder` writes conventional ICNS chunks. PNG data is retained for the large/retina chunks. The ic04 and ic05 chunks use premultiplied ARGB channel planes with literal RLE packets to avoid a measured alpha-association defect in this host's iconutil encoder. The format choice is backed by actual iconutil output and decode experiments, not an invented icon format. See the research report for rejected alternatives.

`ConversionValidator` independently invokes the installed system iconutil to decode the final ICNS. It checks all ten names and dimensions, alpha availability and visible content. Packaging compares every normalized premultiplied sRGB pixel against its source rendition, including the complete canvas and alpha. Any difference fails the conversion. `ImageComparison` provides the separate development-only reference metrics and difference/side-by-side PNGs; it does not silently crop or rescale mismatched canvases.

## Outputs and file-system behavior

The ten slots are 16@1×, 16@2×, 32@1×, 32@2×, 128@1×, 128@2×, 256@1×, 256@2×, 512@1× and 512@2×, covering 16...1024 physical pixels. The optional PNG and UI preview are the same rendered 1024 master as the final ICNS.

`TemporaryWorkspace` creates UUID directories with mode 0700 and removes them on success, handled failure and cancellation. Independent jobs never share build paths, bundle identifiers or output staging directories. Process logs are private temporary files, with a bounded diagnostic tail in memory.

`OutputPublisher` stages files on the export volume after validation. With no replacement consent, it uses an atomic hard-link creation that fails if the destination already exists, including a race with another converter. With explicit consent it uses atomic rename and backs up existing files. Files in a multi-output transaction are prepared first and rolled back on handled failures. A crash between the ICNS and PNG renames can leave only one exported file; there is no cross-file atomic filesystem transaction. If restoration itself fails, recovery backups are retained and their path is reported instead of being deleted.

`BatchPlanner` keeps the source basename and appends `(2)`, `(3)`, etc. for names that would collide within a batch, considering case and diacritics. Existing destination files require an explicit confirmation in the app or `--replace` in the CLI.

## Processes and cancellation

`ProcessRunner` uses executable URLs and separate argument arrays, never a shell. Both output streams are drained into a regular file to avoid pipe-buffer deadlocks. Nonzero exits preserve bounded diagnostics. Cancellation/timeout sends SIGTERM, then SIGKILL if the launched tool remains alive after two seconds, and waits for it to be reaped before workspace cleanup. Apple tools can create their own helper processes; process-tree-wide shutdown has not been proved. Unique workspaces prevent cross-job overwrites.

## SwiftUI frontend

`ConversionViewModel` owns imports, selection, preview/conversion tasks, statuses and diagnostics. It accepts only valid packages, deduplicates imports, keeps the UI responsive during processing, cancels obsolete preview requests, and runs batch jobs sequentially. Errors are per-job so one failed input does not stop later independent jobs. Successful jobs retain an in-memory PNG preview even if PNG export is disabled.

`ContentView` supplies drag/drop and NSOpenPanel import, a selectable list, same-pipeline preview, export-folder selection, optional PNG, progress, cancellation, diagnostics and Finder reveal. Only current Default rendering is offered. A visible experimental notice states that reference differences and unvalidated appearance/version modes remain.

The presentation model is also compiled in a test-only package target. Its tests do not create windows, run panels or launch the app. All GUI verification is source review and compilation as requested.

## Sandboxing and distribution

After automatic approval review requested clarification, the user explicitly authorized disabling App Sandbox. The app target now uses `ENABLE_APP_SANDBOX=NO` for Debug and Release. A build condition derived from this setting disables the external rendering pipeline if sandboxing is re-enabled in a future build. The CLI and app share the same verified conversion service.

App Sandbox is distinct from the Codex execution sandbox used during research. The latter demonstrably prevented Apple's renderers from opening valid documents; that observation alone is not proof of App Sandbox incompatibility. Existing app entitlements grant user-selected read-only access, insufficient for folder export. The current backend also executes installed developer tools and uses IconServices. The sandboxed application pipeline has **not** been validated. Apple's [inheritance guidance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html) and [helper-tool guidance](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app) describe inherited rights and signed embedded helpers. The current design cannot re-sign or embed Apple's internal developer tools, and does not attempt temporary permission exceptions or an escape helper. A properly designed sandbox/XPC variant would be separate work.

The authorized local-utility configuration changes only this app target's Debug and Release sandbox setting, retaining Hardened Runtime. It does not disable system security, remove quarantine, change privacy controls or require root. Both configurations were ad-hoc signed for local use and their entitlements inspected. Developer ID signing, notarization, distribution and App Store suitability remain unvalidated.

Release bundle identifier: `com.lloydME.IconMator`. Debug: `com.lloydME.IconMator.beta`. Xcode generates CFBundleIdentifier from each configuration-specific PRODUCT_BUNDLE_IDENTIFIER; both final built plists were inspected. The visible name remains IconMator.
