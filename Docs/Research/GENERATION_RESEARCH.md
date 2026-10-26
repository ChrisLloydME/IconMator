# Rendering generation research: macOS 26 and macOS 27

Research date: 2026-10-26. Status: **explicit generation selection implemented and structurally validated for all six generation × appearance combinations on the recorded host. Interactive visual acceptance and a macOS 26 host run were not performed.**

## Question

IconMator already selected Default, Dark or Mono appearance and always rendered
with the macOS SDK 27 toolchain. This research asks whether the selected Xcode's
Icon Composer renderer can render the same source for either documented macOS
design generation, and how that choice relates to the SDK and the host system.

The answer is yes when the selected renderer advertises and accepts
`--design-generation 26|27`. Generation selection is independent of the SDK used
to discover and run the tools. It is also not the same thing as running Finder on
that macOS version.

## Environment and evidence sources

| Item | Value |
| --- | --- |
| Host | macOS 27.0.1 (26A434), arm64 |
| Selected developer directory | `/Applications/Xcode.app/Contents/Developer` |
| Xcode | 27.1 (27A9275) |
| Active macOS SDK | 27.0 |
| Bundled Icon Composer renderer | `/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool` |
| Renderer version | 27.1, internal build 129 |
| ICNS decoder | `/usr/bin/iconutil` |

Apple documents switching design generations in
[Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer?changes=l_2&language=objc)
and the [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes?changes=l_2_3&language=objc).
The installed renderer's own help output is the direct local capability evidence:

```text
ictool input-document --export-image --output-file <path>
  --platform <platform> --rendition <rendition>
  --width <width> --height <height> --scale <scale>
  [--design-generation <26 or 27>]
```

The implementation inspects `--version` and `--help` on the executable discovered
from the selected Xcode. It does not hardcode this path, assume a particular help
layout, or parse version strings to decide whether the option exists. A narrow
token search tracks `--export-image`, `--rendition` and `--design-generation`.
If the selected renderer does not expose all three, Composer-dependent
combinations are reported as unavailable; the host generation is never substituted.

## Direct renderer evidence

Metadatics (authorized private fixture, not committed) was rendered directly at
1024 × 1024 with the same explicit rendition for both generations. All six direct
outputs were 16-bit Display P3 with alpha and a full-bleed `(0,0,1024,1024)` alpha
canvas. The direct export is not the final macOS icon canvas.

| Rendition | Generation 26 vs 27 RGBA MAE | Max channel | Different pixels | Alpha MAE | Solid bounds |
| --- | --- | --- | --- | --- | --- |
| `Default` | 8.060069799423218 | 143 | 937,561 | 0 | `(0,0) 1024×1024` both |
| `Dark` | 7.672589540481567 | 133 | 949,510 | 0 | `(0,0) 1024×1024` both |
| `ClearLight` (Mono) | 5.409738540649414 | 93 | 878,253 | 0 | `(0,0) 1024×1024` both |

The existing retained report at
[Comparisons/Metadatics-generations/comparison.json](Comparisons/Metadatics-generations/comparison.json)
records the direct `Default` measurement. The generation argument changes
rendered material/colour, not the alpha silhouette of this source.

## Final system presentation evidence

The production Composer path packages the generation-specific artwork into a
temporary legacy ICNS, then obtains the final canvas through public
`NSWorkspace.icon(forFile:)`. The system applies the same application-icon geometry
to both generations:

| Property | Generation 26 and 27 final output |
| --- | --- |
| Dimensions | 1024 × 1024 |
| Normalized format | 8-bit sRGB premultiplied RGBA |
| Alpha ≥ 1 bounds | `(67,76) 890×888` |
| Alpha ≥ 128 bounds | `(100,100) 824×824` |
| Transparent pixels | 312,480 |

Final-image comparisons for Metadatics, over the complete 1024² canvas after the
same 8-bit sRGB normalization:

| Appearance | Generation 26 vs 27 RGBA MAE | Max channel | Different pixels | Alpha MAE | Result |
| --- | --- | --- | --- | --- | --- |
| Default | 5.686609268188477 | 162 | 614,851 | 0 | [default.json](Comparisons/Generation-Final-26-vs-27/default.json) |
| Dark | 4.862878799438477 | 137 | 614,310 | 0 | [dark.json](Comparisons/Generation-Final-26-vs-27/dark.json) |
| Mono (`ClearLight`) | 3.461517810821533 | 87 | 564,921 | 0 | [mono.json](Comparisons/Generation-Final-26-vs-27/mono.json) |

These are material/colour differences after system presentation, not a geometry
difference. They demonstrate that requesting generation 26 does not silently
emit the generation 27 image.

The final generation 26 output is intentionally different from the direct
generation 26 artwork: the renderer's artwork is a full-bleed design canvas
(`(0,0) 1024×1024`), while the final export has the macOS application-icon body
and shadow (`(100,100) 824×824` body, `(67,76) 890×888` including the faintest
shadow). No manual scale, offset, shadow or margin is applied; the current host's
public system presentation supplies that geometry.

## Default regression

macOS 27 + Default on this macOS 27 host remains on the existing compiled-asset
and `NSWorkspace` backend. The new CLI output was compared with the previously
accepted local Default PNG:

- Whole-canvas comparison: **0 differing pixels**, RGBA MAE `0`, maximum channel
  difference `0`, alpha MAE `0`.
- Both files have SHA-256
  `a59c8751743902e405a55eec7d545a40be34b940ed63c1a9f3a2a8730ab75bd5`.
- The accepted geometry is unchanged: `(100,100) 824×824` solid bounds and
  `(67,76) 890×888` visible bounds.
- The exported ICNS is also byte-identical to the accepted previous file
  (SHA-256 `49dd4536b22a16fe7b11b68c86f2e4b0ad32b052d6e7ce352017d8a72367b512`).

See [Comparisons/Generation-Default-Regression/comparison.json](Comparisons/Generation-Default-Regression/comparison.json).
The previous reference image remains a private local artifact and is not
committed.

## Routing decision

| Request | Host | Backend | Generation argument |
| --- | --- | --- | --- |
| macOS 27 + Default | known macOS 27 | Compiled assets + system presentation | none; host generation matches the request |
| macOS 27 + Default | macOS 26, unknown or future | Icon Composer + system presentation | `27` |
| macOS 26 + Default | any | Icon Composer + system presentation | `26` |
| macOS 27 or 26 + Dark | any | Icon Composer + system presentation | requested generation |
| macOS 27 or 26 + Mono | any | Icon Composer + system presentation | requested generation |

The compiled path is not used for generation 26. On a future host it is also not
assumed to be generation 27. This is deliberately conservative: the host-dependent
path is retained only where its current generation is known to match the request.
The SDK remains the selected Xcode's macOS 27 SDK in every row.

## Capability and identity model

`RenderCapabilities` reports all six combinations with:

- requested generation and appearance;
- supported state and the backend that would handle it;
- effective Composer rendition (`Default`, `Dark`, `ClearLight`);
- whether the combination requires Composer;
- an actionable reason when unavailable;
- the actual tool identity that produced the result.

`DeveloperTools.identity` now includes the Composer version and parsed
`--export-image` / `--rendition` / `--design-generation` interface in addition to
the developer directory, Xcode version, host version, SDK path/version and
Composer path. Previews and output state are keyed by that identity. Conversion
rechecks it before rendering and requires refreshed capabilities if the renderer
changed.

## Validation matrix

The real integration test runs:

```text
2 generations × 3 appearances × 3 sources
```

Sources on this run: repository `IconMator/AppIcon.icon`, a generated layered
synthetic icon, and the authorized local Metadatics fixture. For every result it
checks the requested/effective options, genuine 1024 master, preserved alpha,
complete-canvas geometry, all ten ICNS representations, independent
`iconutil` decoding with exact normalized pixel equality, and input-byte
preservation. It also verifies that at least one source differs between
generations and that at least one source differs between appearances.

Results are recorded in the [validation report](VALIDATION_REPORT.md).

## Limitations

- The final static image is presented by the current host's IconServices. The
  selected generation controls Apple's artwork/material rendering; it does not
  emulate every Finder, Dock or runtime material behaviour of a different macOS
  installation.
- No macOS 26 host was available. Rendering generation 26 on macOS 27 does not
  prove all host presentation details match Finder running on macOS 26.
- No independent Finder reference exists for generation 26. The evidence is the
  renderer's explicit generation output, final geometry, structural validation and
  measured differences from generation 27.
- The exporter is a static snapshot. It does not preserve live materials, layer
  editability or runtime appearance behaviour.
- SDK 27 remains required. This feature does not support SDK 26, switch Xcode
  installations or enumerate SDKs.
- Only the recorded host and Xcode were exercised with real rendering. Other SDK
  27 environments are accepted by policy but are not individually certified.

## Reproduction

```sh
# Discover tools, Composer version/help and generation-aware capabilities.
.build/native/debug/iconmator tools

# Convert one complete request with diagnostics.
.build/native/debug/iconmator convert \
  ReferenceInputs/Metadatics/Metadatics.icon \
  .research/GenerationValidation/Metadatics-26-mono.icns \
  --generation 26 --appearance mono --png --replace --diagnostics

# Compare final generation outputs; generated PNGs remain ignored.
.build/native/debug/iconmator compare \
  .research/GenerationValidation/Metadatics-26-default.png \
  .research/GenerationValidation/Metadatics-27-default.png \
  .research/GenerationValidation/compare-26-27-default
```

The six-combination CLI run is recorded in
[Logs/generation-conversions.txt](Logs/generation-conversions.txt); the
generation-aware `tools` output is in
[Logs/generation-tools.json](Logs/generation-tools.json).
