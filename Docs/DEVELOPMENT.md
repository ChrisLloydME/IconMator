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

Default uses the compiled-asset backend. Dark and Mono additionally require the
Icon Composer renderer bundled with the selected Xcode. Their verified renditions
are `Dark` and `ClearLight`; Mono is the untinted light clear variant. A missing
or unreadable Composer renderer disables only Dark and Mono, with an actionable
capability reason; it never silently falls back to Default.

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
.build/native/debug/iconmator convert "AppIcon.icon" "AppIcon.icns" --appearance dark --png
```

`--appearance` accepts `default`, `dark`, or `mono` and defaults to `default`.
`--png` exports the same rendered 1024 master. Existing destinations are refused
unless `--replace` is explicitly supplied. `--diagnostics` prints tool output,
the rendition/backend, actual source dimensions and final geometry. `tools` prints
the discovered tools plus an `appearanceCapabilities` object containing the
Composer path/version and each appearance's supported state, backend, rendition
and unavailable reason. `package-png` does not accept `--appearance`.

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
never substitutes mocked rendering output. The appearance matrix converts all
three sources with Default, Dark and Mono, decodes every ICNS independently and
checks input-byte preservation.

The GUI has not been launched for verification. UI checks use source review,
presentation-model tests and builds. Appearance selection, preview invalidation,
late-result rejection and batch appearance capture are covered without launching
the app. Finder custom-icon display and interactive visual acceptance remain
separate, unperformed checks. See the
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
