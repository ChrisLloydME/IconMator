# Validation report

Date: 2026-10-26. Host: macOS 27.0.1 (26A434), Xcode 27.1 (27A9275), arm64.

Status: conversion engine and frontend implementation exist and compile. Default, Dark and Mono have real-output validation; **full product acceptance remains open**. The user explicitly authorized local non-sandboxed app builds; both configurations have been rebuilt and ad-hoc signed. This report does not claim interactive GUI, Finder display or independent Dark/Mono Finder-reference testing.

## SDK 27 compatibility policy update

The exact host/Xcode build gate has been replaced with a check of the selected
macOS SDK's reported major version: all 27.x releases, including Beta and RC, are allowed. Xcode selection
still follows DEVELOPER_DIR or xcode-select; no installation scanning was added.
The historical measurements below remain tied to the stated host. References to
an exact environment gate in the earlier research describe the previous policy,
not the current runtime restriction. Structural checks remain enabled and do not
automatically establish visual fidelity on untested toolchains.

The maintainer has accepted the current output's visual appearance. This is
user-provided visual acceptance, not GUI inspection performed by an agent.

SDK-policy verification: the full 39-test suite (12 presentation + 27 core,
including real Apple-tool integration) passed on the recorded host. After adding
explicit Beta/RC suffix recognition, non-GUI tests passed again, including 18 SDK
version boundary cases and a different Xcode Beta/OS fixture. Debug and Release
application builds passed. Only SDK 27.0 was installed for real rendering; other
27.x and prerelease versions were policy tests, not real toolchain executions.


## Executed checks

| Check | Result | Evidence |
| --- | --- | --- |
| Debug application build, local ad-hoc signing | PASS | [appearance-debug-build.txt](Logs/appearance-debug-build.txt) |
| Release application build, local ad-hoc signing | PASS | [appearance-release-build.txt](Logs/appearance-release-build.txt) |
| Debug generated CFBundleIdentifier | com.lloydME.IconMator.beta | Inspected built Debug Info.plist with PlistBuddy |
| Release generated CFBundleIdentifier | com.lloydME.IconMator | Inspected built Release Info.plist with PlistBuddy |
| Full Swift test suite including real-tool integration | PASS: 38 tests, 8 suites | [appearance-tests.txt](Logs/appearance-tests.txt) |
| Appearance matrix, 3 sources × Default/Dark/Mono | PASS: complete canvas, transparent alpha, all ten decoded representations and exact packaging round trips | AppleIntegrationTests `appearanceMatrixPreservesCanvasPackagingAndInputs`; [appearance-tests.txt](Logs/appearance-tests.txt) |
| Default output regression against the prior system backend | PASS: byte-identical 1024 PNG | Whole-canvas comparison, 0 differing pixels |
| Dark/Mono rendering against appearance-specific system references | PASS within measured bounds: RGBA MAE 1.20/1.00, alpha MAE 0.0019, solid bounds identical | [APPEARANCE_RESEARCH.md](APPEARANCE_RESEARCH.md) |
| CLI Default/Dark/Mono conversions with diagnostics | PASS: expected renditions/backends; final canvas alpha bounds recorded | [appearance-conversions.txt](Logs/appearance-conversions.txt) |
| PNG reference → ICNS → independent iconutil decode | Exact normalized 1024 RGBA match; all ten source renditions retained | [comparison.json](Comparisons/Final-reference-roundtrip/comparison.json) |
| Metadatics .icon → ICNS + PNG | PASS structural and packaging gates; reference differences below | [convert-Metadatics.txt](Logs/convert-Metadatics.txt) |
| Tunes, AudioMator, SwiftBiomes complete conversion | PASS; all ten decoded renditions compared internally | Docs/Research/Logs/convert-*.txt |
| Two simultaneous real rendering jobs | PASS; distinct outputs, preserved input bytes | AppleIntegrationTests |
| Spaces, Unicode and shell-special characters | PASS | Real integration input path and Process argument test |
| Cancellation and timeout | PASS; real process tests and Default/Dark conversion cancellation leave no completed output | AppleIntegrationTests; EngineTests |
| Atomic collision refusal, approved replacement, staged cleanup | PASS | EngineTests |
| Relocated Xcode, DEVELOPER_DIR app override, Command Line Tools rejection | PASS | ToolDiscoveryTests (discovery mocks only) |
| Missing/unsupported toolchain, invalid input, symlinks, small master | PASS | EngineTests |
| Missing Composer, unreadable Composer version, route without fallback, CLI malformed appearance arguments | PASS | AppearanceTests |
| Appearance preview invalidation, late-result rejection, batch appearance capture, output/appearance association | PASS | AppearancePresentationTests; no GUI launched |
| Full-canvas dimensions, geometry, alpha metrics and diff generation | PASS | ImageAnalysisTests |
| Import deduplication, selection removal, invalid-import feedback, sandbox gating, batch naming | PASS | PresentationTests; no GUI launched |
| Package-aware picker validation, selecting newly imported files, automatic preview | PASS | ImportWorkflowTests; picker delegate and model only, no panel displayed |
| UI layout/flow source review | Reviewed | ContentView.swift, ConversionViewModel.swift and IconImportPanel.swift |
| Finder custom-icon visual display, multi-scale visual review | NOT PERFORMED | No GUI verification per instruction |
| Independent Finder Dark/Mono reference | NOT AVAILABLE | Appearance-specific system renderer used as the measurement reference |
| macOS 26 runtime, other Xcode/host builds, generation selection | Other SDK 27 environments allowed but not individually validated; generation selection unavailable | SDK-family gate |
| Actual local app entitlements and Hardened Runtime | App Sandbox absent; `ENABLE_HARDENED_RUNTIME=YES`; Release signature has runtime flag. Debug ad-hoc signing reports hardened runtime disabled, as Xcode emitted during the build. | Built Info.plists, build settings, `codesign` output |
| Sandboxed app execution, Developer ID/notarization/distribution | NOT VALIDATED | Explicit scope limitation |

Commands:

```sh
swift test --disable-sandbox --scratch-path .build/native
ICONMATOR_INTEGRATION=1 swift test --disable-sandbox --scratch-path .build/native
xcodebuild -project IconMator.xcodeproj -scheme IconMator -configuration Debug -derivedDataPath .research/AppDerived CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
xcodebuild -project IconMator.xcodeproj -scheme IconMator -configuration Release -derivedDataPath .research/AppDerived CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
.build/native/debug/iconmator convert ReferenceInputs/Metadatics/Metadatics.icon .research/Appearances/Implementation/Metadatics-dark.icns --appearance dark --png --replace --diagnostics
.build/native/debug/iconmator convert ReferenceInputs/Metadatics/Metadatics.icon .research/Appearances/Implementation/Metadatics-mono.icns --appearance mono --png --replace --diagnostics
.build/native/debug/iconmator package-png ReferenceInputs/Metadatics/Metadatics.png Examples/Metadatics/Reference.icns
iconutil -c iconset Examples/Metadatics/Converted.icns -o .research/FinalDecoded/Converted.iconset
.build/native/debug/iconmator compare ReferenceInputs/Metadatics/Metadatics.png .research/FinalDecoded/Converted.iconset/icon_512x512@2x.png Research/Comparisons/Final-converted-reference
```

The local 2026-10-26 agent harness could not run SwiftPM's nested
`sandbox-exec`, so the SwiftPM commands used `--disable-sandbox`. The same harness
also needed a writable `HOME` (`.research/home`) and a relaxed outer sandbox for
Xcode's SwiftPM integration; those are harness constraints, not product
requirements. Apple rendering commands required execution outside the harness
sandbox. This does not modify system sandbox/privacy settings. Initial failures
were used to improve the implementation; successful rerun logs are authoritative.
Ordinary tests explicitly skip the Apple integration tests unless
`ICONMATOR_INTEGRATION=1`; enabled integration tests require the real user-supplied
Metadatics fixture and use the repository AppIcon plus a synthetic layered icon.
They never substitute successful mock output.

## Reference fidelity

The target is the user-confirmed `ReferenceInputs/Metadatics/Metadatics.png`. The supplied ICNS was explicitly rejected by the user and is excluded. The PNG has no embedded ICC profile and is interpreted as sRGB by ImageIO.

| Whole 1024² canvas comparison | Reference PNG packaged to ICNS | Source .icon converted to ICNS |
| --- | --- | --- |
| RGBA mean absolute difference, 0...255 | 0 | 0.129457 |
| Maximum channel difference | 0 | 5 |
| Alpha mean absolute difference | 0 | 0.001935 |
| Maximum alpha difference | 0 | 1 |
| Alpha >=128 bounds | (100,100,824,824) | (100,100,824,824) |
| Alpha >=1 bounds | (67,75,890,890) | (67,76,890,888) |
| Classification | Exact after 8-bit sRGB normalization | Numerically close; visual acceptance pending |

The extreme shadow fringe differs at alpha level 1; no arbitrary padding, scaling or color compensation was applied. This is not a claim of pixel-perfect source rendering. The final ICNS packaging itself is lossless after the explicit comparison normalization for all ten representations on every successful conversion. Original reference and output files are preserved.

The engine's metric comparison utility conservatively labels every non-exact comparison as requiring visual review. Reports and difference/side-by-side PNGs are generated under Docs/Research/Comparisons; PNG comparison artifacts are Git-ignored and remain local. No screenshots were taken and no native app was launched for inspection.

## Appearance validation

Rendition selection was established with the bundled Icon Composer renderer, not by
UI labels. `Dark` and `ClearLight` are the explicit verified values; Mono maps to
`ClearLight` (untinted light clear). `ClearDark` is a distinct control and is not
exposed by the single Mono option.

The navigation levels are reported separately:

| Level | Result |
| --- | --- |
| ICNS structure and lossless packaging | PASS: all ten representations, genuine 1024 master, preserved alpha, exact normalized pixel equality between each packaging source and independently decoded representation |
| Apple appearance selection | PASS for the requested renditions: `Dark`, `ClearLight`; undefined `Clear`/`Tinted` fail clearly; no silent fallback observed |
| Canvas and geometry | PASS: direct 1024 design body is presented through public NSWorkspace as a 1024 system canvas, solid bounds (100, 100) 824 × 824, with the system drop shadow; no manual scale/shadow |
| Fidelity to an independent reference | Dark/Mono: no separate Finder reference. Appearance-specific system renderer used as measurement reference; RGBA MAE 1.1995 (Dark) / 1.0037 (Mono), alpha MAE 0.0019, maximum alpha 1. Default retains its measured Finder-reference comparison. |

The complete appearance study, exact commands, valid/invalid rendition probes and
color-normalization measurements are in
[APPEARANCE_RESEARCH.md](APPEARANCE_RESEARCH.md). The production path does not use
the private research probe. Interactive visual acceptance and Finder display were
not performed under the no-GUI instruction.

## Dataset and scope gaps

Metadatics supplies three translucent layers, a P3 gradient, shadows and boundary detail. Tunes, AudioMator and SwiftBiomes are additional real structural/round-trip controls, but lack Finder-reference PNGs. They do not establish fidelity across all requested categories. Transparent/partial backgrounds, stronger refraction and alternate edge geometries still need explicit paired references. Only the recorded host/toolchain has measured fidelity evidence; the runtime policy now allows the macOS SDK 27 family.

## Acceptance tracking

- Implemented: imports, multi-file thumbnail navigation, Default/Dark/Mono appearance selection with automatic same-pipeline preview, sequential batch naming, folder export, optional PNG, cancellation, progress, errors, overwrite confirmation, Finder reveal action, independent ten-size ICNS validation, input-byte preservation, stale-preview and stale-export protection.
- Verified without GUI: engine conversion, real concurrent jobs, 1024 master, alpha preservation through packaging, all appearance renditions, system canvas/shadow geometry, both app builds, distinct bundle identifiers, presentation-model behavior.
- Completed configuration: user-authorized non-sandboxed Debug/Release, local ad-hoc signatures. `ENABLE_HARDENED_RUNTIME=YES`; the Release signature carries the runtime flag, while Xcode reported runtime disabled for the ad-hoc Debug signature.
- Pending: interactive UI behavior; Finder custom-icon appearance; multi-scale visual review; independent Finder Dark/Mono references; broader paired references; macOS 26 support; signed distribution.

A successful build or iconutil exit alone is never treated as evidence of fidelity. Product acceptance must remain qualified until the pending checks are resolved.


## Import and preview redesign

The user's feedback confirmed drag/drop worked, while Choose Files could not select `.icon` documents. The old picker depended on an extension-derived content type and disallowed directory selection. The revised picker explicitly supports directory packages and validates the document contents on confirmation; ordinary folders remain available for navigation. Delegate tests cover valid `.icon` directories, malformed packages, unrelated files and folder navigation. Actual panel interaction is still unperformed under the no-GUI instruction.

The sidebar has been removed. A single area handles empty-state import and selected-icon preview; additional files appear in a thumbnail tray. Newly imported files automatically become the preview selection, including when another icon was already selected. The bottom area contains destination/PNG options and Finder, Diagnostics and conversion controls. Tests use a mock preview provider only to check presentation orchestration; real rendering continues to run in the separate Apple integration suite. Both redesigned app configurations compile, pass local signature verification and retain their distinct identifiers.


Example artwork binaries are excluded from the distributed repository and are
purged from Git history at the maintainer's request. The JSON metrics and
original research commentary remain; private reference inputs and generated
images are not covered by the project's MIT license. Historical commands retain their original `Examples/Metadatics` paths as an
execution record, not distributed files. To reproduce them privately, create that
ignored directory and supply your own authorized inputs.

The captured Apple actool manual was also removed from the repository and Git
history. The recorded `man actool` command remains the way to inspect it locally.
