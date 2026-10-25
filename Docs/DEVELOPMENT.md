# Development

Run all commands from the repository root.

## Requirements and Tool Selection

The currently validated conversion environment is macOS 27.0.1 (26A434) with
Xcode 27.1 (27A9275), including its SDK and bundled Icon Composer. The application
target is macOS 26.0+, but unvalidated rendering environments are rejected.

Tool discovery honors `DEVELOPER_DIR`, otherwise uses `xcode-select -p`. It resolves
installed tools and the SDK through xcrun rather than hardcoding an Xcode location.
Finish Xcode's first-launch setup before conversion. Do not bundle Apple's
internal tools with the application. No third-party packages are required.

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
the recorded validation. Xcode 27 marks this build-system option deprecated; it
remains documented here to reproduce those verified commands.

```sh
swift build --build-system native --scratch-path .build/native
.build/native/debug/iconmator tools
.build/native/debug/iconmator convert "AppIcon.icon" "AppIcon.icns" --png
```

`--png` exports the same rendered 1024 master. Existing destinations are refused
unless `--replace` is explicitly supplied. `--diagnostics` prints tool output and
actual source dimensions for each requested representation.

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
swift test --build-system native --scratch-path .build/native
```

Real Apple-tool integration tests:

```sh
ICONMATOR_INTEGRATION=1 swift test --build-system native --scratch-path .build/native
```

The integration suite needs authorized local fixtures at
`ReferenceInputs/Metadatics/Metadatics.icon` and `ReferenceInputs/Metadatics/Metadatics.png`.
They are intentionally excluded from Git. Integration tests are explicitly skipped
by default; enabling them never substitutes mocked rendering output.

The GUI has not been launched for verification. UI checks use source review,
presentation-model tests and builds. Finder custom-icon display and multi-scale
visual acceptance remain separate, unperformed checks. See the
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
