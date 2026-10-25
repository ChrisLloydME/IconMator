# Validation report

Date: 2026-10-25. Host: macOS 27.0.1 (26A434), Xcode 27.1 (27A9275), arm64.

Status: conversion engine and frontend implementation exist and compile. The engine has real-output validation; **full product acceptance remains open**. The user explicitly authorized local non-sandboxed app builds; both configurations have been rebuilt and ad-hoc signed with Hardened Runtime retained. This report does not claim interactive GUI or Finder display testing.

## Executed checks

| Check | Result | Evidence |
| --- | --- | --- |
| Debug application build, local ad-hoc signing | PASS | Research/Logs/ui-redesign-debug-build.txt |
| Release application build, local ad-hoc signing | PASS | Research/Logs/ui-redesign-release-build.txt |
| Debug generated CFBundleIdentifier | com.lloydME.IconMator.beta | Inspected built Debug Info.plist with PlistBuddy |
| Release generated CFBundleIdentifier | com.lloydME.IconMator | Inspected built Release Info.plist with PlistBuddy |
| Full Swift test suite including real-tool integration | 25 tests PASS, 6 suites | Research/Logs/ui-redesign-tests.txt |
| PNG reference → ICNS → independent iconutil decode | Exact normalized 1024 RGBA match; all ten source renditions retained | Research/Comparisons/Final-reference-roundtrip/comparison.json |
| Metadatics .icon → ICNS + PNG | PASS structural and packaging gates; reference differences below | Research/Logs/convert-Metadatics.txt |
| Tunes, AudioMator, SwiftBiomes complete conversion | PASS; all ten decoded renditions compared internally | Research/Logs/convert-*.txt |
| Two simultaneous real rendering jobs | PASS; distinct outputs, preserved input bytes | AppleIntegrationTests |
| Spaces, Unicode and shell-special characters | PASS | Real integration input path and Process argument test |
| Cancellation and timeout | PASS | Real process tests; rendering-orchestration cancellation leaves no completed output |
| Atomic collision refusal, approved replacement, staged cleanup | PASS | EngineTests |
| Relocated Xcode, DEVELOPER_DIR app override, Command Line Tools rejection | PASS | ToolDiscoveryTests (discovery mocks only) |
| Missing/unsupported toolchain, invalid input, symlinks, small master | PASS | EngineTests |
| Full-canvas dimensions, geometry, alpha metrics and diff generation | PASS | ImageAnalysisTests |
| Import deduplication, selection removal, invalid-import feedback, sandbox gating, batch naming | PASS | PresentationTests; no GUI launched |
| Package-aware picker validation, selecting newly imported files, automatic preview | PASS | ImportWorkflowTests; picker delegate and model only, no panel displayed |
| UI layout/flow source review | Reviewed | ContentView.swift, ConversionViewModel.swift and IconImportPanel.swift |
| Finder custom-icon visual display, multi-scale visual review | NOT PERFORMED | No GUI verification per instruction |
| macOS 26 runtime, other Xcode/host builds, Dark/Mono/generation selection | NOT VALIDATED; unavailable | Exact environment gate |
| Actual local app entitlements and Hardened Runtime | Inspected after ad-hoc signing; no App Sandbox entitlement | Research/Logs/*entitlements.txt, release-signature.txt |
| Sandboxed app execution, Developer ID/notarization/distribution | NOT VALIDATED | Explicit scope limitation |

Commands:

```sh
ICONMATOR_INTEGRATION=1 swift test --build-system native --scratch-path .build/native
xcodebuild -project IconMator.xcodeproj -scheme IconMator -configuration Debug -derivedDataPath .research/AppDerived CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
xcodebuild -project IconMator.xcodeproj -scheme IconMator -configuration Release -derivedDataPath .research/AppDerived CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
.build/native/debug/iconmator package-png ReferenceInputs/Metadatics/Metadatics.png Examples/Metadatics/Reference.icns
.build/native/debug/iconmator convert ReferenceInputs/Metadatics/Metadatics.icon Examples/Metadatics/Converted.icns --png
iconutil -c iconset Examples/Metadatics/Converted.icns -o .research/FinalDecoded/Converted.iconset
.build/native/debug/iconmator compare ReferenceInputs/Metadatics/Metadatics.png .research/FinalDecoded/Converted.iconset/icon_512x512@2x.png Research/Comparisons/Final-converted-reference
```

Apple rendering commands required execution outside the Codex sandbox. This does not modify system sandbox/privacy settings. Initial failures were used to improve the implementation; successful rerun logs are authoritative. Ordinary tests explicitly skip two integration tests unless ICONMATOR_INTEGRATION=1; enabled integration tests require the real user-supplied fixture and never substitute successful mock output.

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

The engine's metric comparison utility conservatively labels every non-exact comparison as requiring visual review. Reports and difference/side-by-side PNGs are generated under Research/Comparisons; PNG comparison artifacts are Git-ignored and remain local. No screenshots were taken and no native app was launched for inspection.

## Dataset and scope gaps

Metadatics supplies three translucent layers, a P3 gradient, shadows and boundary detail. Tunes, AudioMator and SwiftBiomes are additional real structural/round-trip controls, but lack Finder-reference PNGs. They do not establish fidelity across all requested categories. Transparent/partial backgrounds, stronger refraction and alternate edge geometries still need explicit paired references. The supported host/toolchain is intentionally narrow pending that evidence.

## Acceptance tracking

- Implemented: imports, multi-file thumbnail navigation, automatic same-pipeline preview, sequential batch naming, folder export, optional PNG, cancellation, progress, errors, overwrite confirmation, Finder reveal action, independent ten-size ICNS validation, input-byte preservation.
- Verified without GUI: engine conversion, real concurrent jobs, 1024 master, alpha preservation through packaging, tests, both app builds, distinct bundle identifiers, presentation-model behavior.
- Completed configuration: user-authorized non-sandboxed Debug/Release, local ad-hoc signatures, preserved Hardened Runtime.
- Pending: interactive UI behavior; Finder custom-icon appearance; multi-scale visual review; broader paired references; macOS 26 support; signed distribution.

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
