# Development

Run all commands from the repository root.

## Requirements and Tool Selection

Conversion accepts the selected Xcode’s active macOS SDK when its reported major
version is 27 (including beta and RC SDKs), using `xcrun --sdk macosx --show-sdk-version`. Exact Xcode and host
builds are not restricted; the app deployment target remains macOS 26.0+.
Missing tools, unsupported SDK families and invalid outputs are still rejected.
The measured rendering environment remains macOS 27.0.1 (26A434) with Xcode 27.1
(27A9275); other SDK 27 environments are allowed but not individually certified.

Tool discovery honors `DEVELOPER_DIR`, otherwise uses `xcode-select -p`. It resolves
installed tools and the SDK through xcrun rather than hardcoding an Xcode location.
Finish Xcode's first-launch setup before conversion. Do not bundle Apple's
internal tools with the application. No third-party packages are required.

Routing depends on the complete generation/appearance request, not appearance
alone. macOS 27 + Default on a known macOS 27 host keeps the accepted
compiled-asset backend. macOS 26 rendering, Dark, and Mono use the Icon Composer
renderer bundled with the selected Xcode, passing an explicit
`--design-generation 26|27`. Their verified renditions are `Default`, `Dark`, and
`ClearLight`; Mono is the untinted light clear variant. The renderer's `--version`
and `--help` tokens are inspected; a missing renderer, unreadable version, or
absent `--design-generation` interface disables only the combinations that need
Composer, with an actionable capability reason. The host generation is never
substituted and there is no silent fallback. Selecting generation 26 does not
change the selected Xcode, the active macOS SDK or the deployment target.

```sh
xcode-select -p
xcodebuild -version
```

The app uses Swift 5 language mode; the shared Swift package uses Swift 6. Both are
compiled by the selected Xcode toolchain.

## Application Builds

Open `IconMator.xcodeproj` and build the IconMator scheme. Reproducible local builds:

```sh
xcodebuild -project IconMator.xcodeproj -scheme IconMator \
  -configuration Debug -derivedDataPath .research/AppDerived \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build

xcodebuild -project IconMator.xcodeproj -scheme IconMator \
  -configuration Release -derivedDataPath .research/AppDerived \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

Products are under `.research/AppDerived/Build/Products/Debug` and `Release`.
These commands ad-hoc sign for local use; they do not produce notarized distribution.

The 2026-10-26 agent harness additionally ran these commands with
`HOME=$PWD/.research/home` and its outer sandbox relaxed, because Xcode's SwiftPM
integration invokes a nested `sandbox-exec` that the harness denies. Those are
harness constraints, not project requirements; the project commands themselves are
unchanged.

| Configuration | Bundle identifier |
| --- | --- |
| Debug | `com.lloydME.IconMator.beta` |
| Release | `com.lloydME.IconMator` |

The visible app name remains IconMator. Both configurations disable App Sandbox
for the local developer-tool pipeline and retain Hardened Runtime. Re-enabling
sandboxing disables the unvalidated external rendering workflow in the UI.

The application icon is compiled directly from `IconMator/AppIcon.icon`, including
a full-size standalone ICNS fallback. No Downloads path is used during builds.
LICENSE and THIRD_PARTY_NOTICES.md are copied into the application resources.

## Command-Line Converter

The commands below use the same native SwiftPM build system and scratch path as
the recorded validation. Xcode 27 marks `--build-system native` deprecated; the
local 2026-10-26 harness also blocks SwiftPM's nested `sandbox-exec`, so the
actual validated commands use `--disable-sandbox`. That flag changes only the
manifest/build sandbox, not the compiled product.

```sh
swift build --disable-sandbox --scratch-path .build/native
.build/native/debug/iconmator tools
.build/native/debug/iconmator convert "AppIcon.icon" "AppIcon.icns" \
  --generation 26 --appearance dark --png
.build/native/debug/iconmator convert "AppIcon.icon" "AppIcon.icns" \
  --generation 27 --appearance mono --png
```

`--generation` accepts only `26` or `27` and defaults to `27`. `--appearance`
accepts `default`, `dark`, or `mono` and defaults to `default`; the two options are
independent. `--png` exports the same rendered 1024 master. Existing destinations
are refused unless `--replace` is explicitly supplied. `--diagnostics` prints the
requested rendering and appearance separately from host, Xcode and SDK versions,
the effective Composer rendition/backend, the exact generation argument, actual
source dimensions and final geometry. `tools` prints the discovered tools plus a
`renderCapabilities` object containing the tool identity, Composer path/version
and parsed interface (`--export-image`, `--rendition`, `--design-generation`), and
all six combinations with supported state, backend, rendition and unavailable
reason. `package-png` accepts neither `--appearance` nor `--generation`, because
its input is already rendered.

Development-only image and reference commands:

```sh
.build/native/debug/iconmator inspect "image.png"
.build/native/debug/iconmator compare "reference.png" "candidate.png" .research/comparison
.build/native/debug/iconmator package-png "master.png" "reference.icns"
```

PNG packaging requires a genuine 1024 × 1024 image with alpha; it never upscales
a small master or adds icon margins. Comparison preserves the full canvas and
normalizes a separate working representation to 8-bit premultiplied sRGB.

## Automated Tests

Non-GUI unit and presentation-model tests:

```sh
swift test --disable-sandbox --scratch-path .build/native
```

Real Apple-tool integration tests:

```sh
ICONMATOR_INTEGRATION=1 swift test --disable-sandbox --scratch-path .build/native
```

The integration suite needs authorized local fixtures at
`ReferenceInputs/Metadatics/Metadatics.icon` and `ReferenceInputs/Metadatics/Metadatics.png`.
They are intentionally excluded from Git. It also uses the repository's
`IconMator/AppIcon.icon` and a synthetic layered icon created in its temporary
workspace. Integration tests are explicitly skipped by default; enabling them
never substitutes mocked rendering output. The generation matrix converts all
three sources with both generations and all three appearances (18 conversions),
decodes every ICNS independently, checks the complete-canvas geometry and exact
packaging round trip, verifies the requested generation/appearance/backend, and
checks input-byte preservation. It also renders both generations directly with
the selected Composer executable to prove that the argument changes the artwork.
The macOS 27 + Default comparison against the accepted prior output remains exact
on the recorded host.

The GUI has not been launched for verification. UI checks use source review,
presentation-model tests and builds. Generation/appearance selection, preview
invalidation, late-result rejection, tool-identity invalidation and batch option
capture are covered without launching the app. Finder custom-icon display and
interactive visual acceptance remain separate, unperformed checks. See the
[validation report](Research/VALIDATION_REPORT.md) for the exact evidence.

## Repository Layout

```text
IconMator/          SwiftUI app, import policy and application icon
Sources/           Reusable conversion core and CLI
Tests/             Swift package unit, presentation and integration tests
IconMatorTests/    Xcode app-hosted test target
IconMatorUITests/  Xcode UI test target; not run during non-GUI validation
Docs/              Guides, notices, branding and retained research evidence
LICENSE            MIT license for original project code/documentation
```

Local builds, private reference inputs and generated artwork remain ignored. Do
not reintroduce research artwork or copied Apple manuals into the source archive.
