# Appearance research: Default, Dark and Mono

Research date: 2026-10-26. Status: **verified rendering path implemented; Default preserved on its existing backend; interactive visual acceptance not performed.**

## Environment and tools

| Item | Value |
| --- | --- |
| Host | macOS 27.0.1 (26A434), arm64 |
| Selected developer directory | `/Applications/Xcode.app/Contents/Developer` (from `xcode-select -p`) |
| Xcode | 27.1 (27A9275) |
| Bundled Icon Composer renderer | `/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool` |
| Renderer version | 27.1, internal build 129 (`ictool --version`) |
| ICNS decoder | `/usr/bin/iconutil` |
| Asset compiler | selected Xcode's `actool` |

`xcrun ictool` is not the renderer. The executable above, discovered from the selected Xcode, is the renderer used by the experiments and the implementation.

The renderer's published usage is:

```text
ictool input-document --export-image --output-file <path>
  --platform <platform> --rendition <rendition>
  --width <width> --height <height> --scale <scale>
  [--tint-color <color>] [--tint-strength <strength>]
  [--design-generation <26 or 27>]
```

All experiments used absolute paths, separate process arguments (no shell), and disposable copies in `.research/Appearances/`. Original `.icon` packages were not modified.

## Rendition names

`--help` does not enumerate rendition names. Passing an invalid value produces a clear failure:

```text
$ ictool ... --rendition Clear
Unknown rendition name: Clear. Should be one of “Default”, “Dark”,
“TintedLight”, “TintedDark”, “ClearLight” or “ClearDark”
exit 255
```

The accepted names on this host are:

| Rendition | Result |
| --- | --- |
| `Default` | Default appearance |
| `Dark` | Dark appearance |
| `TintedLight` | Tinted (light) |
| `TintedDark` | Tinted (dark) |
| `ClearLight` | Mono / clear (light) |
| `ClearDark` | Mono / clear (dark) |

`Mono` is also accepted by this renderer and produces output byte-identical to
`ClearLight` for the tested sources, but it is not listed in the documented set.
The implementation uses the documented `ClearLight` value rather than relying on
the undocumented alias.

`Clear` and `Tinted` are rejected with exit 255. No successful exit or silent
fallback was observed for invalid rendition names. The experiments also confirmed
that `Dark`, `ClearLight` and `ClearDark` produce different images from `Default`
and from each other on sources whose design produces appearance differences.

## What the system extraction path does

The compiled-assets backend obtains its icon through public
`NSWorkspace.icon(forFile:)` while `.aqua` is the current drawing appearance.
Requesting the same bundle under `.darkAqua` or
`.accessibilityHighContrastDarkAqua` produced:

| Comparison | Different pixels | RGBA MAE | Maximum channel | Alpha MAE | Maximum alpha |
| --- | --- | --- | --- | --- | --- |
| `.aqua` vs `.darkAqua` | 1 | 0.000000238 | 1 | 0 | 0 |

This is not a Dark icon. It is a one-level rendering difference in a single
pixel, and the alpha channel is identical. The system extraction path therefore
cannot select Dark or Mono through `NSAppearance`. No global appearance or Dock
preference was changed.

## Direct Composer geometry

Direct `ictool` output at 1024 × 1024 is a **full-bleed design canvas**, not the
final macOS application-icon canvas:

| Measurement | Direct Default 1024 |
| --- | --- |
| Pixel dimensions | 1024 × 1024 |
| Bits per component | 16 |
| Color space | Display P3 |
| Alpha | Present |
| Alpha ≥ 1 bounds | (0, 0, 1024, 1024) |
| Alpha ≥ 128 bounds | (0, 0, 1024, 1024) |
| Transparent pixels | 62,532 |

The icon body touches the canvas edges. The system's ordinary compiled-asset
rendering puts the same design at 824 × 824 within a 1024 × 1024 canvas:

| Measurement | Compiled-asset system render |
| --- | --- |
| Alpha ≥ 1 bounds | (67, 76) 890 × 888 |
| Alpha ≥ 128 bounds | (100, 100) 824 × 824 |
| Transparent pixels | 312,480 |

A manual scale of 824/1024 plus a 100-pixel offset reproduced the solid bounds but
could not reproduce the system drop shadow outside the 824-pixel body. Scaling the
design is not a complete mapping, and inventing a shadow would violate the project's
rendering rules.

## Verified geometry solution: legacy ICNS presentation

The system will apply the normal macOS app-icon canvas and shadow to an
appearance-specific artwork if that artwork is supplied as a **legacy application
ICNS** rather than as compiled `.icon` assets:

1. Render the requested appearance with `ictool` at 1024 × 1024.
2. Normalize the complete canvas once to explicit 8-bit sRGB.
3. Package the normalized master as a temporary legacy `AppIcon.icns`.
4. Create a fresh temporary application bundle containing that ICNS and a stub
   executable. The application is never launched.
5. Extract the icon with the existing public `NSWorkspace.icon(forFile:)` path.

The system supplies the macOS presentation (824-pixel body at (100, 100),
the system drop shadow, and the complete transparent 1024 canvas). No manual
scale, offset, shadow, mask or Default alpha is used.

Measurements for Metadatics across all appearances:

| Appearance | Final 1024 alpha ≥ 1 | Final 1024 alpha ≥ 128 | Transparent pixels |
| --- | --- | --- | --- |
| Default | (67, 75) 890 × 890 | (100, 100) 824 × 824 | 311,491 |
| Dark | (67, 75) 890 × 890 | (100, 100) 824 × 824 | 311,491 |
| Mono (`ClearLight`) | (67, 75) 890 × 890 | (100, 100) 824 × 824 | 311,491 |
| `ClearDark` control | (67, 75) 890 × 890 | (100, 100) 824 × 824 | 311,491 |

The final-system-reference comparison used a research-only private
`ISImageDescriptor` probe. Production does **not** use private API. The probe was
used only to obtain independent Dark and Clear system references for measurement.
The production path uses `ictool` plus public `NSWorkspace`.

### Fidelity against the system appearance references

The following used the same appearance-specific artwork, the legacy ICNS
presentation, and the system's own compiled-asset renderer as a reference. Values
are over the complete 1024² canvas after 8-bit premultiplied sRGB normalization.

| Target | RGBA MAE | Maximum channel | Alpha MAE | Maximum alpha | Solid bounds |
| --- | --- | --- | --- | --- | --- |
| Default | 1.1020 | 185 | 0.001935 | 1 | (100, 100) 824 × 824 both |
| Dark | 1.1995 | 209 | 0.001904 | 1 | (100, 100) 824 × 824 both |
| Mono (`ClearLight`) | 1.0037 | 126 | 0.001904 | 1 | (100, 100) 824 × 824 both |
| `ClearDark` control | 1.1256 | 191 | 0.001904 | 1 | (100, 100) 824 × 824 both |

The remaining difference is concentrated at the one-pixel shadow-boundary
difference between the reference bundle and the temporary bundle, plus
resampling/quantization at edges. It is not a geometry mismatch: the complete
canvas and solid bounds agree. The maximum-channel values occur at antialiased
edges, not across the body.

## Color handling

Direct `ictool` output on this host is 16-bit Display P3. A legacy ICNS containing
unconverted P3 data was interpreted substantially differently by the legacy icon
path (RGBA MAE 22.9 against the Default system reference), so the implementation
does not feed the raw direct export to the legacy path.

The production sequence is:

1. Render the verified rendition directly at 1024 × 1024.
2. Draw the complete canvas once into explicit 8-bit premultiplied sRGB,
   preserving alpha and using `.none` tone mapping when the source reports
   extended-range content.
3. Package that normalized master into the temporary legacy ICNS with the
   existing project ICNS builder.
4. Extract the system-presented 1024 canvas and normalize it with the same
   explicit sRGB policy used by the existing compiled-asset backend.

This avoids a P3-profile interpretation error while retaining the existing
documented sRGB output policy. It does not crop, pad or tone-map by an invented
amount.

## Selection decision

| Requested appearance | Backend | Icon Composer rendition |
| --- | --- | --- |
| Default | Compiled assets + system extraction (unchanged) | `Default` (not used by the Default backend) |
| Dark | Composer direct render + legacy ICNS system presentation | `Dark` |
| Mono | Composer direct render + legacy ICNS system presentation | `ClearLight` |

Mono is the untinted clear/light variant. `ClearDark` is a distinct dark clear
variant and is available from the renderer, but it is not exposed by this UI: the
product has one Mono option and a separate Dark option. If the product later needs
Mono to follow system light/dark, `ClearDark` is the verified candidate; it must be
a separate, explicit choice rather than an implicit fallback.

## Remaining gaps

- No independent Finder Dark or Mono reference was available. Apple's own
  appearance-specific system renderer was used as the measurement reference. This
  establishes rendition selection, geometry and approximate color behavior, not
  Finder-equivalent fidelity for every possible source.
- Interactive visual acceptance and Finder display were not performed, per the
  no-GUI verification instruction.
- The direct renderer's legacy ICNS presentation was measured on macOS 27.0.1 with
  Xcode 27.1. The current policy allows other OS/Xcode combinations when the
  selected macOS SDK is 27.x; those combinations remain unmeasured here.
- The research reference probe uses a private framework and is not part of the
  application or test suite. It is retained only as local `.research/` evidence.

## Reproduction commands

```sh
# Escape the current harness sandbox for SwiftPM if needed:
swift build --disable-sandbox --scratch-path .build/native

# Valid/invalid rendition probes:
ictool ReferenceInputs/Metadatics/Metadatics.icon \
  --export-image --output-file .research/Appearances/Metadatics-Dark.png \
  --platform macOS --rendition Dark --width 1024 --height 1024 --scale 1

ictool ReferenceInputs/Metadatics/Metadatics.icon \
  --export-image --output-file /tmp/invalid.png \
  --platform macOS --rendition Clear --width 1024 --height 1024 --scale 1

# System extraction appearance comparison (research reproduction):
# The extractor is reproduced under .research/Appearances/Tools/ExtractAppearances.swift.

# Apply the legacy ICNS presentation:
.build/native/debug/iconmator package-png .research/Appearances/Direct-Dark-sRGB.png \
  .research/Appearances/Legacy-Dark.icns --replace
# Then extract Legacy-Dark.icns through a temporary app bundle with NSWorkspace.
```

Generated originals and normalized copies remain under ignored
`.research/Appearances/`; no private artwork or Apple executable is committed.
