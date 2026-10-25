# Rendering research

Research date: 2026-10-25. Status: **fidelity gate open; no production backend selected yet**.

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

`Research/Logs` preserves compiler/tool diagnostics. Initial sandbox failures and the initial Swift initialization error are distinguished from successful reruns. No padding/scaling was applied in these experiments. Original sources are untouched; local copies and compiled artifacts live under ignored `.research/` and `ReferenceInputs/`.

## Results so far

Four real sources tested: user-provided Metadatics (three translucent layers, P3 gradient), Tunes, AudioMator, SwiftBiomes. Only Metadatics has a user-provided Finder reference; the other three are structural controls, not proof of Finder fidelity.

| Experiment | Measured result | Interpretation |
| --- | --- | --- |
| Direct Metadatics preview, generation 27 | 1024², 16-bit P3 RGBA; alpha >=128 bounds (0,0,1024,1024) | Wrong application-icon geometry without a validated transformation; rejected as-is |
| Direct generation 26 vs 27 | Same alpha; normalized RGBA MAE 8.0601/255 | Parameter changes rendering; neither mode validated against its respective OS |
| Standalone actool | All ten standard iconset representations, 16 through 1024 px | Structural success |
| Tunes actool vs complete Xcode build | Whole ICNS SHA-256 identical: `ef9a6c3d1320a1eb3ae47cf813bc16f62d7b639728e6a9c6ab43c918b8601af9` | Building a whole app adds no fidelity to the standalone ICNS for this sample |
| Metadatics actool vs Finder PNG | Alpha >=128 bounds both (100,100,824,824); RGBA MAE 6.8642; alpha MAE 2.6591 | Same nominal solid geometry does not prove rendering fidelity; candidate not accepted |
| Supplied reference ICNS vs supplied PNG | Solid bounds differ by 10 px vertically; RGBA MAE 11.2576; alpha MAE 5.0546 | Supplied ICNS itself is not equivalent to the supplied PNG; PNG remains the reference |

All errors above are measured over the **entire** 1024² canvas after 8-bit premultiplied sRGB normalization. Source images remain unchanged. Alpha >=1 includes shadows; alpha >=128 describes the stronger silhouette. JSON results and generated difference/side-by-side PNGs are under `Research/Comparisons`. The comparison does not automatically label a non-exact result a close match.

The reference PNG has no embedded profile; ImageIO interprets it as sRGB. This limits attribution of color differences. Alpha/geometry mismatches cannot be explained by RGB color profiles alone.

## Next investigation and gate

Evaluate public `NSWorkspace.icon(forFile:)` against a **complete built app**, drawing offscreen into explicit sRGB rather than serializing an extended-range floating-point CGImage directly. A resource-only synthetic `.app` can return a generic application icon and is not a valid rendering reference. No GUI, screenshots, Finder automation, or application launch is used.

The final GUI must wait until a strategy satisfies the rendering gate. A valid ICNS and matching outer dimensions alone do not pass it. Finder visual assignment and inspection at multiple scales remain unperformed under the user's no-GUI restriction.

## Sources consulted

- [Michael Tsai: margins](https://mjtsai.com/blog/2025/10/02/how-to-export-a-mac-icon-file-with-the-proper-margins/) — motivation for testing compiled output; not treated as a substitute for current measurements.
- [CodexBar build script](https://github.com/steipete/CodexBar/blob/main/Scripts/build_icon.sh) — reviewed; its 824+padding method is not copied.
- [Apple Icon Composer](https://developer.apple.com/icon-composer/) — current materials, generation and appearance context.
- [Creating your app icon](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer) and [build settings](https://developer.apple.com/documentation/xcode/build-settings-reference) — online detail pages require JS; local actool manual and Xcode build specification provide directly inspectable command evidence.
