# Rendering research

Research date: 2026-10-25. Status: **working prototype evaluated; compiled-assets + IconServices backend selected for the researched environment. Final visual acceptance remains open.**

## Environment

- Host: macOS 27.0.1, build 26A434; arm64.
- Selected developer directory: `/Applications/Xcode.app/Contents/Developer`, discovered with `xcode-select -p`.
- Xcode 27.1, build 27A9275; bundled Icon Composer 27.1, internal tool build 129.
- Compiler: selected Xcode Swift toolchain. System `/usr/bin/iconutil`.
- `xcrun ictool` resolves an asset-compiler frontend, **not** the Icon Composer preview executable. Its `--help` is rejected.
- Actual renderer: developer directory's sibling `Applications/Icon Composer.app/Contents/Executables/ictool`. No separate Icon Composer installation was found by Spotlight. Other Xcode installations have not been exhaustively excluded.
- This execution sandbox prevents both preview and asset-compiler icon document access. Running these tools outside it succeeds. This is separate from App Sandbox distribution feasibility.
- Downloads access was denied by macOS privacy controls even outside the execution sandbox. The user supplied a workspace copy under `ReferenceInputs/Metadatics`.

## Commands and parameters

Local help documents:

```text
ictool input-document --export-image --output-file <path>
  --platform <platform> --rendition <rendition>
  --width <width> --height <height> --scale <scale>
  [--tint-color <color>] [--tint-strength <strength>]
  [--design-generation <26 or 27>]
ictool --version
```

Both generation values execute successfully for macOS/Default. This establishes command support, not fidelity to both OS versions. The older positional `--export-preview` interface is not used.

The installed actool manual documents `--standalone-icon-behavior default|all|none`. The installed `AssetCatalogCompiler.xcspec` confirms that `ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR=all` passes `--standalone-icon-behavior all`.

Commands actually executed (paths abbreviated relative to repository; executable paths resolved from the selected developer directory):

```sh
sw_vers
xcode-select -p
xcodebuild -version
xcrun --find actool
xcrun --find iconutil
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" --help
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" --version
man actool
# Preview, run with absolute input and output URLs:
ictool INPUT.icon --export-image --output-file OUTPUT.png --platform macOS --rendition Default --width 1024 --height 1024 --scale 1 --design-generation 27
# Asset compilation, run with absolute paths:
xcrun actool INPUT.icon --compile OUTPUT_DIR --platform macosx --minimum-deployment-target 26.0 --app-icon INPUT --standalone-icon-behavior all --output-partial-info-plist OUTPUT_DIR/partial.plist --output-format human-readable-text
iconutil -c iconset OUTPUT.icns -o OUTPUT.iconset
# Complete application control build (never launched):
xcodebuild -project .research/XcodeProbe/IconMator.xcodeproj -scheme IconMator -configuration Debug -derivedDataPath .research/ProbeDerived CODE_SIGNING_ALLOWED=NO build
swift build --build-system native --scratch-path .build/native
swift test --build-system native --scratch-path .build/native
.build/native/debug/iconmator compare REFERENCE.png CANDIDATE.png COMPARISON_DIRECTORY
```

`Docs/Research/Logs` preserves compiler/tool diagnostics. Initial sandbox failures and the initial Swift initialization error are distinguished from successful reruns. No padding/scaling was applied in these experiments. Original sources are untouched; local copies and compiled artifacts live under ignored `.research/` and `ReferenceInputs/`.

## Results so far

Four real sources tested: user-provided Metadatics (three translucent layers, P3 gradient), Tunes, AudioMator, SwiftBiomes. Only Metadatics has a user-provided Finder reference; the other three are structural controls, not proof of Finder fidelity.

| Experiment | Measured result | Interpretation |
| --- | --- | --- |
| Direct Metadatics preview, generation 27 | 1024², 16-bit P3 RGBA; alpha >=128 bounds (0,0,1024,1024) | Wrong application-icon geometry without a validated transformation; rejected as-is |
| Direct generation 26 vs 27 | Same alpha; normalized RGBA MAE 8.0601/255 | Parameter changes rendering; neither mode validated against its respective OS |
| Standalone actool | All ten standard iconset representations, 16 through 1024 px | Structural success |
| Tunes actool vs complete Xcode build | Whole ICNS SHA-256 identical: `ef9a6c3d1320a1eb3ae47cf813bc16f62d7b639728e6a9c6ab43c918b8601af9` | Building a whole app adds no fidelity to the standalone ICNS for this sample |
| Metadatics actool vs Finder PNG | Alpha >=128 bounds both (100,100,824,824); RGBA MAE 6.8642; alpha MAE 2.6591 | Same nominal solid geometry does not prove rendering fidelity; candidate not accepted |
| Supplied ICNS | Excluded following user clarification | The PNG alone defines the desired appearance |

All errors above are measured over the **entire** 1024² canvas after 8-bit premultiplied sRGB normalization. Source images remain unchanged. Alpha >=1 includes shadows; alpha >=128 describes the stronger silhouette. JSON results and generated difference/side-by-side PNGs are under `Docs/Research/Comparisons`. The comparison does not automatically label a non-exact result a close match.

The reference PNG has no embedded profile; ImageIO interprets it as sRGB. This limits attribution of color differences. Alpha/geometry mismatches cannot be explained by RGB color profiles alone.

## Selected strategy and completed prototype

A complete Xcode build of Metadatics and a fresh, minimal C application bundle containing the same actool assets produce **byte-identical** 1024² PNGs when extracted using the same public NSWorkspace/CoreGraphics procedure. Metadatics standalone ICNS also matches Xcode's whole-file hash (`d0de466ec51570570409d4050ce4ceee1c2d20518f1ce4b0068a132c87bdd04a`), but that standalone ICNS is not the desired runtime appearance.

Selected pipeline:

1. Validate input and copy the complete package into an isolated workspace.
2. Invoke selected Xcode's actool with standalone behavior all; independently decode all compiled renditions and require the 1024 master.
3. Compile our own `int main(void) { return 0; }` stub with selected clang and an explicitly resolved macOS SDK. Place assets and the executable in a unique `.app` bundle with unique identity. **Never launch it.**
4. Request the app icon via public `NSWorkspace.icon(forFile:)` under Aqua/Default appearance, at each required pixel size. Require a source at least as large as the request. Reject the generic application fallback.
5. Render into explicit 8-bit sRGB using the documented CoreGraphics `.none` tone-mapping mode for extended-range sources. Do not add margins or effects. Duplicate only equal-size renditions.
6. Package conventional static ICNS, independently decode using system iconutil, and require exact normalized RGBA equality for **every** rendition before publishing.

Fresh bundle URLs and identities are essential. A previously queried incomplete bundle can retain a generic application icon after its contents are corrected. The core prototype always queries a complete, fresh bundle.

### HDR color investigation

NSWorkspace supplies a 16-bit floating-point extended-sRGB CGImage with content headroom 1.2 (measured calculated headroom about 1.122 for Metadatics). Ordinary sRGB drawing applies automatic tone mapping and dims the result: reference RGBA MAE 1.25375/255. Direct PNG encoding of a float image is also unsuitable as a faithful static export. Explicit `.none` tone mapping avoids that automatic brightness change; this is a documented color conversion policy, not an empirical color correction or simulated Liquid Glass effect.

Against the confirmed target PNG, the final source conversion measures:

- Entire 1024² canvas; solid alpha >=128 bounds exactly `(100,100,824,824)`.
- RGBA MAE **0.129457/255**, maximum channel difference **5/255**.
- Alpha MAE **0.001935/255**, maximum **1/255**.
- Reference alpha >=1 bounds `(67,75,890,890)`; output `(67,76,890,888)`. The remaining faintest shadow pixels differ at quantization level 1.
- Not an exact match. The untagged reference, floating-point rendering and raster quantization limit color attribution. No arbitrary compensation is introduced.

The user confirmed that `Metadatics.png` is the target and the supplied `.icns` was copied incorrectly; the latter is excluded from decisions.

### ICNS packaging investigation

A real round-trip test revealed iconutil 27-era behavior on this host: `ic04` and `ic05` ARGB chunks change partially transparent RGB values while preserving alpha (16px example: max normalized delta 61, MAE 3.25293/255). Allowing that error would defeat the packaging gate.

Experiments retained under `Docs/Research/Comparisons/Packaging-*` demonstrate that explicitly encoding **premultiplied** ARGB channel planes in the actual `ic04`/`ic05` codec fixes the defect: exact normalized matches after independent iconutil decoding at 16 and 32 pixels. Other renditions preserve their original PNG payloads. An attempted `icp4` PNG alternative was rejected because the local decoder did not preserve it. A straight-alpha ARGB experiment was also rejected. These rejected encoders are not used by the application.

`IconFamilyEncoder` now writes the same conventional chunk types observed in Apple's own output: ic04, ic11, ic05, ic12, ic07, ic13, ic08, ic14, ic09, ic10. ARGB uses literal RLE packets; no third-party codec is bundled. Every generated file still passes the independent ten-rendition pixel gate; unexpected codec changes cause a failure rather than degraded output.

`Examples/Metadatics/Reference.icns` packages the user-provided PNG; its decoded 1024 master matches the target exactly after normalization. `Converted.icns` and `Converted.png` come from the new `.icon` engine, with the measured rendering differences above. No input files are changed.

### Scope and remaining acceptance

The feasibility gate for implementing the small UI is satisfied by a working, independently decoded real conversion. This is an **experimental local utility**, not a claim of completed visual acceptance. Runtime support is deliberately restricted to the exact researched combination (macOS 27.0.1 build 26A434, Xcode 27.1 build 27A9275). The app can target macOS 26, but unvalidated conversion environments are disabled. No 26/27, Dark or Mono selector is offered.

Multiple local sources are structural controls, but only one Finder reference is available. Transparent backgrounds, additional boundary geometries and stronger refraction need reference fixtures. Finder custom-icon display and visual review at multiple scales remain unperformed under the no-GUI verification instruction. The output is a static snapshot; editable layers and runtime material behavior are not preserved.

## Sources consulted

- [Michael Tsai: margins](https://mjtsai.com/blog/2025/10/02/how-to-export-a-mac-icon-file-with-the-proper-margins/) — motivation for testing compiled output; not treated as a substitute for current measurements.
- [CodexBar build script](https://github.com/steipete/CodexBar/blob/main/Scripts/build_icon.sh) — reviewed; its 824+padding method is not copied.
- [Apple Icon Composer](https://developer.apple.com/icon-composer/) — current materials, generation and appearance context.
- [Creating your app icon](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer) and [build settings](https://developer.apple.com/documentation/xcode/build-settings-reference) — online detail pages require JS; local actool manual and Xcode build specification provide directly inspectable command evidence.

## Per-resolution extraction observed

The production backend's diagnostic run (`Docs/Research/Logs/convert-Metadatics-diagnostics.txt`) recorded:

| Requested physical pixels | IconServices source pixels | Source component depth |
| --- | --- | --- |
| 1024 | 1024 | 16-bit float |
| 512 | 1024 | 16-bit float |
| 256 | 512 | 16-bit float |
| 128 | 256 | 16-bit float |
| 64 | 128 | 16-bit float |
| 32 | 64 | 16-bit float |
| 16 | 32 | 16-bit float |

Thus the backend requests each size from IconServices and downsamples the returned native source when necessary; it does not derive every rendition by repeatedly scaling one 1024 image. No source is upscaled. The 1024 export remains a full-canvas 1:1 render. These dimensions are observations for this host, not a promise of future API behavior.

Final full conversions of Tunes, AudioMator and SwiftBiomes also passed the exact per-rendition decode gate. They remain structural controls without paired Finder references.


Example artwork binaries are excluded from the distributed repository and are
purged from Git history at the maintainer's request. The JSON metrics and
original research commentary remain; private reference inputs and generated
images are not covered by the project's MIT license. Historical commands retain their original `Examples/Metadatics` paths as an
execution record, not distributed files. To reproduce them privately, create that
ignored directory and supply your own authorized inputs.

The captured Apple actool manual was also removed from the repository and Git
history. The recorded `man actool` command remains the way to inspect it locally.
