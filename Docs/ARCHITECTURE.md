# Architecture

IconMator consists of a Swift 6 package and the existing SwiftUI Xcode application. The app links the local `IconConversionCore` library; the `iconmator` executable exercises the same implementation without launching the UI. There are no third-party packages and no network calls in application code.

## Rendering pipeline

`IconConversionService` validates the input package, output location and selected developer environment. The source must be a readable directory with an `.icon` extension, valid `icon.json` and a `groups` array. Symbolic links inside the package are rejected. Output inside the input package is refused. Input files are never edited.

`DeveloperToolLocator` honors `DEVELOPER_DIR` (including an Xcode app URL), otherwise reads `xcode-select -p`. It resolves actool, clang and the SDK using xcrun, discovers the selected Xcode's bundled Composer executable, and records Xcode version/build and host version/build. It also inspects the renderer's `--version` output and its `--help` tokens for `--export-image`, `--rendition` and `--design-generation`; no installation path or exact help layout is assumed. It does not assume Xcode resides in `/Applications/Xcode.app`. Required executable paths are checked again before work; changes to the active selection, recorded versions, Composer version or parsed Composer interface cause an explicit failure. Conversion requires a reported macOS SDK major version of 27 (including beta and RC releases), obtained with `xcrun --sdk macosx --show-sdk-version`; exact OS/Xcode builds are not restricted. SDK path and version, the Composer path/version and the parsed interface are included in tool identity and rechecked before preview/conversion. This compatibility policy does not certify rendering fidelity across every SDK 27 environment. Missing Composer or a renderer without explicit generation selection affects only combinations routed to Composer.

`IconRenderingBackend` separates rendering from orchestration. `IconRenderingRouter` routes a complete `IconRenderOptions` (generation + appearance):

| Request | Backend |
| --- | --- |
| macOS 27 + Default on a known macOS 27 host | `CompiledAssetBackend` (existing accepted path) |
| macOS 27 + Default on any other or unknown host | `ComposerRenderingBackend`, `--design-generation 27` |
| macOS 26 + Default | `ComposerRenderingBackend`, `--design-generation 26` |
| Either generation + Dark or Mono | `ComposerRenderingBackend`, requested generation and rendition |

The compiled path is never used for generation 26 and is not assumed to represent a future host's rendering. The selected Xcode and macOS SDK are unchanged by this decision.

`CompiledAssetBackend` only accepts Default, generation 27 and a host whose macOS major version is 27; any other request fails before rendering rather than silently following the host. It:

1. Copies the input into a unique private temporary workspace as `AppIcon.icon`.
2. Invokes actool directly for macOS, deployment target 26.0, Default app icon, standalone behavior `all`.
3. Independently decodes the compiled ICNS and checks all required dimensions, alpha channels and nonempty content. Requires both the high-resolution compiled rendition and Assets.car.
4. Compiles our own minimal C stub using the selected clang and SDK. Creates a complete temporary `.app` with that executable and the compiled resources. Each bundle has a fresh URL and identifier; the app is **never launched**.
5. Uses public NSWorkspace under Aqua/Default appearance to obtain system-rendered images at each required size. Source images smaller than the request are rejected. The generic application icon is rejected. Equal-size 1×/2× slots share bytes.
6. Renders into sRGB with preserved alpha and explicit no-tone-mapping for extended-range HDR sources. It never synthesizes Liquid Glass, adds padding, clips artwork to a custom mask, creates shadows, or scales an already correct master to an assumed inner size.

`ComposerRenderingBackend` handles every request routed to it, including Default for generation 26:

1. Requires the selected renderer's version and parsed help interface. It refuses to omit `--design-generation` or substitute the host generation; a renderer without the required interface makes the combination unavailable.
2. Copies the input into the same kind of isolated temporary workspace and never edits the original package.
3. Invokes the selected Xcode's bundled `ictool` with explicit `--design-generation 26|27` and an explicit, verified rendition: `Default`, `Dark`, or `ClearLight` for Mono. Mono is the untinted light clear variant; `ClearDark` is a distinct variant and is not exposed by the single Mono control.
4. Validates the direct 1024 × 1024 alpha output and normalizes the complete canvas once to explicit 8-bit sRGB. It does not crop, pad or add effects.
5. Packages that normalized master as a temporary legacy `AppIcon.icns`, then creates a fresh temporary application bundle with a stub executable. The temporary ICNS is not the exported ICNS and the app is never launched.
6. Extracts the final icon through the same public `NSWorkspace` path. The current host supplies the macOS application-icon canvas and drop shadow; no manual scale/offset or Default alpha is used. This is why generation selection controls the material artwork but does not emulate every Finder behaviour of a different macOS installation.
7. Packages the extracted representations and independently decodes the final ICNS. Every representation must match its packaging source exactly after normalized sRGB comparison.

System icon extraction runs on MainActor because it uses AppKit. Tool processes and expensive validation execute asynchronously outside the SwiftUI model. There is no automatic lower-fidelity rendering fallback.

`RenderCapabilities` describes all six generation/appearance combinations without rendering a matrix: supported state, effective backend, rendition, whether Composer is required and an actionable reason when unavailable. It records the tool identity that produced the result. The UI and `tools` CLI use the same model; conversion rechecks the identity and capability immediately before work.

`ICNSBuilder` packages the native requested representations. For the development-only PNG packaging command, it copies the genuine 1024² master unchanged and uses CoreGraphics high-quality interpolation separately from that master for smaller sizes. This path does not accept or upscale a low-resolution master.

`IconFamilyEncoder` writes conventional ICNS chunks. PNG data is retained for the large/retina chunks. The ic04 and ic05 chunks use premultiplied ARGB channel planes with literal RLE packets to avoid a measured alpha-association defect in this host's iconutil encoder. The format choice is backed by actual iconutil output and decode experiments, not an invented icon format. See the [rendering research](Research/RENDERING_RESEARCH.md) for rejected alternatives.

`ConversionValidator` independently invokes the installed system iconutil to decode the final ICNS. It checks all ten names and dimensions, alpha availability and visible content. Packaging compares every normalized premultiplied sRGB pixel against its source rendition, including the complete canvas and alpha. Any difference fails the conversion. `ImageComparison` provides the separate development-only reference metrics and difference/side-by-side PNGs; it does not silently crop or rescale mismatched canvases.

## Outputs and file-system behavior

The ten slots are 16@1×, 16@2×, 32@1×, 32@2×, 128@1×, 128@2×, 256@1×, 256@2×, 512@1× and 512@2×, covering 16...1024 physical pixels. The optional PNG and UI preview are the same rendered 1024 master as the final ICNS. The complete generation and appearance options apply consistently to the preview, PNG and ICNS. Changing either clears preview/export state associated with the previous request.

`TemporaryWorkspace` creates UUID directories with mode 0700 and removes them on success, handled failure and cancellation. Independent jobs never share build paths, bundle identifiers or output staging directories. Process logs are private temporary files, with a bounded diagnostic tail in memory.

`OutputPublisher` stages files on the export volume after validation. With no replacement consent, it uses an atomic hard-link creation that fails if the destination already exists, including a race with another converter. With explicit consent it uses atomic rename and backs up existing files. Files in a multi-output transaction are prepared first and rolled back on handled failures. A crash between the ICNS and PNG renames can leave only one exported file; there is no cross-file atomic filesystem transaction. If restoration itself fails, recovery backups are retained and their path is reported instead of being deleted.

`BatchPlanner` keeps the source basename and appends `(2)`, `(3)`, etc. for names that would collide within a batch, considering case and diacritics. Existing destination files require an explicit confirmation in the app or `--replace` in the CLI.

## Processes and cancellation

`ProcessRunner` uses executable URLs and separate argument arrays, never a shell. Both output streams are drained into a regular file to avoid pipe-buffer deadlocks. Nonzero exits preserve bounded diagnostics. Cancellation/timeout sends SIGTERM, then SIGKILL if the launched tool remains alive after two seconds, and waits for it to be reaped before workspace cleanup. Apple tools can create their own helper processes; process-tree-wide shutdown has not been proved. Unique workspaces prevent cross-job overwrites.

## SwiftUI frontend

`ConversionViewModel` owns imports, selection, rendering generation, appearance, preview/conversion tasks, statuses and diagnostics. It accepts only valid packages, deduplicates imports, keeps the UI responsive during processing, cancels obsolete preview requests, and runs batch jobs sequentially. The complete options snapshot and tool identity are captured at batch start. Generation, appearance or tool changes clear rendered previews, exported-output status and the Reveal target; a late preview result is applied only if its task generation, job ID, options and tool identity still match. Errors are per-job so one failed input does not stop later independent jobs. Successful jobs retain an in-memory PNG preview even if PNG export is disabled.

`ContentView` uses one shared import/preview workspace, with no sidebar. An empty workspace accepts drops or opens NSOpenPanel; after import it displays the selected rendered icon. Multiple inputs use a horizontal thumbnail tray. New imports become the selection, and the model automatically requests their preview without relying on a SwiftUI selection-change callback. The window uses native SwiftUI thin material as its container background, with a darker regular-material preview panel and a subtle adaptive tint, preserving translucency. Compact native menus for rendering generation and appearance share the top header; a standard bordered export-folder button and optional PNG share one row below the workspace. Only the generation/appearance controls use menu selectors; the folder action has no dropdown indicator. Typography uses native `.title2` semibold app and empty-state headings, `.body` text throughout the main-window controls, descriptions, file labels and status, and `.headline` Diagnostics section headings. Point-size overrides in the main window are limited to SF Symbols. Diagnostics uses the same semantic typography instead of shrinking its body/table text to 11–12 points; only annotations and monospaced logs use the smaller supporting style. Footer actions retain their original bordered button style, and SF Symbols use medium weight. The default window is 560 × 620 points with a 520 × 540 minimum; batch thumbnails occupy a bounded 72-point tray. The drop outline appears only during a drag, and the bottom progress area retains a fixed height to prevent layout jumps. Finder reveal, diagnostics and conversion/cancellation actions share the bottom bar. Unavailable combinations show the capability reason and disable conversion rather than silently rendering another generation or appearance. The separate `DiagnosticsView` uses a fixed heading, a scrollable body and a native bottom safe-area bar. Environment, rendering support and logs have padded, rounded section backgrounds. Environment values are aligned in a compact grid; six capabilities form a two-row support matrix with centered green SF Symbol checkmarks for available combinations and red crosses for unavailable ones; backend names remain in help and the copied report; unique unavailable reasons and the selected conversion log remain readable below. Its 520 × 560 material sheet stays narrower than the default window, and Copy Report includes full paths, renditions, reasons and logs even where screen values are truncated. AudioMator’s Acknowledgements sheet served as a layout reference; no source was imported.

`IconImportPanelDelegate` accepts both file and directory selections without relying on extension-to-UTType registration. Its lightweight enablement policy keeps ordinary folders navigable and excludes unrelated files/packages; final validation requires a real, readable `.icon` directory with valid document contents. File/directory flags are applied after the content-type and package settings because macOS 27 can reset them. The delegate remains alive throughout the modal panel session.

The presentation model is also compiled in a test-only package target. Its tests do not create windows, run panels or launch the app. All GUI verification is source review and compilation as requested.

## Sandboxing and distribution

After automatic approval review requested clarification, the user explicitly authorized disabling App Sandbox. The app target now uses `ENABLE_APP_SANDBOX=NO` for Debug and Release. A build condition derived from this setting disables the external rendering pipeline if sandboxing is re-enabled in a future build. The CLI and app share the same verified conversion service.

App Sandbox is distinct from the Codex execution sandbox used during research. The latter demonstrably prevented Apple's renderers from opening valid documents; that observation alone is not proof of App Sandbox incompatibility. Existing app entitlements grant user-selected read-only access, insufficient for folder export. The current backend also executes installed developer tools and uses IconServices. The sandboxed application pipeline has **not** been validated. Apple's [inheritance guidance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html) and [helper-tool guidance](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app) describe inherited rights and signed embedded helpers. The current design cannot re-sign or embed Apple's internal developer tools, and does not attempt temporary permission exceptions or an escape helper. A properly designed sandbox/XPC variant would be separate work.

The authorized local-utility configuration changes only this app target's Debug and Release sandbox setting, retaining Hardened Runtime. It does not disable system security, remove quarantine, change privacy controls or require root. Both configurations were ad-hoc signed for local use and their entitlements inspected. Developer ID signing, notarization, distribution and App Store suitability remain unvalidated.

Release bundle identifier: `com.lloydME.IconMator`. Debug: `com.lloydME.IconMator.beta`. Xcode generates CFBundleIdentifier from each configuration-specific PRODUCT_BUNDLE_IDENTIFIER; both final built plists were inspected. The visible name remains IconMator.
