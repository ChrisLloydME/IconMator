# Appearance implementation handoff

> Historical appearance implementation checkpoint. The later SDK 27 compatibility
> update removes the exact host/Xcode gate described below. See
> [VALIDATION_REPORT.md](VALIDATION_REPORT.md) for the current policy.


Date: 2026-10-26. State: **paused at a clean checkpoint after core, CLI, UI and tests were committed and verified. No implementation work is left uncommitted.**

## Completed work and commits

| Commit | Contents |
| --- | --- |
| `b6e028c` `docs: investigate dark and mono rendering` | Added [APPEARANCE_RESEARCH.md](APPEARANCE_RESEARCH.md) and linked it from the documentation index. |
| `667d725` `feat: add dark and mono rendering backends` | Shared `IconAppearance`, capability reporting, rendition mapping, Composer backend, routing, system-icon extraction refactor, CLI `--appearance` parsing and core tests. |
| `84811db` `feat: add icon appearance selection` | Compact Default/Dark/Mono picker, appearance-aware preview and batch state, stale-preview protection, output/appearance association and presentation tests. |
| `e94620c` `test: verify icon appearance conversion` | Real three-source × three-appearance integration matrix, independent ICNS decoding, input-byte preservation and Dark cancellation cleanup. |
| `cc7e668` `docs: document appearance support` | README, architecture, development, rendering research and validation report updates. |
| `fe6164c` `fix: format appearance geometry diagnostics` | Replaced optional-value debug descriptions with explicit geometry strings in CLI diagnostics. |
| This docs/handoff commit | Adds tracked validation logs, links them from the report, and updates this handoff. |

## Verified facts

| Fact | Evidence |
| --- | --- |
| Host macOS 27.0.1 (26A434), Xcode 27.1 (27A9275), Icon Composer 27.1 (129) | `sw_vers`, `xcodebuild -version`, `ictool --version` |
| Valid renditions: `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark` | Invalid-rendition probe in [APPEARANCE_RESEARCH.md](APPEARANCE_RESEARCH.md); `Clear`/`Tinted` fail exit 255 |
| `Mono` is accepted as an alias and byte-identical to `ClearLight` for tested sources | Metadatics and explicit-source experiments; production uses documented `ClearLight` |
| `ClearDark` is distinct from `ClearLight` | Direct render hashes and system references differ |
| Default output is unchanged | New Default 1024 PNG is byte-identical to the prior system backend output; 0 differing pixels |
| Direct `ictool` art is a 1024 body-only canvas; the system adds the 824 body at (100, 100) plus shadow | Full-canvas alpha profiles and system-reference comparisons |
| Dark and Mono use the system app-icon canvas and shadow, with no manual scale/edit | Solid bounds (100, 100) 824×824; visible bounds 890×890; alpha MAE 0.0019; see research doc |
| Default/Dark/Mono ICNS packaging is lossless | Independent `iconutil` decode and exact normalized pixel comparison for all ten representations |
| Core/UI tests | 38 tests in 8 suites passed, including real integration |
| Debug and Release app builds | Both succeeded on 2026-10-26 |
| Bundle identifiers | Debug `com.lloydME.IconMator.beta`; Release `com.lloydME.IconMator` |
| App Sandbox absent | Built entitlements contain no `com.apple.security.app-sandbox` |
| Hardened Runtime build setting | `ENABLE_HARDENED_RUNTIME=YES`; Release signature carries runtime flag; Xcode reported runtime disabled for ad-hoc Debug signing |

### Actual build/test commands and results

```sh
swift build --disable-sandbox --scratch-path .build/native
# PASS, 2026-10-26

ICONMATOR_INTEGRATION=1 swift test --disable-sandbox --scratch-path .build/native
# PASS: 12 presentation tests + 26 core/integration tests = 38 tests, 8 suites

HOME="$PWD/.research/home" CFFIXED_USER_HOME="$PWD/.research/home" \
  xcodebuild -project IconMator.xcodeproj -scheme IconMator \
  -configuration Debug -derivedDataPath .research/AppDerived \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
# BUILD SUCCEEDED

HOME="$PWD/.research/home" CFFIXED_USER_HOME="$PWD/.research/home" \
  xcodebuild -project IconMator.xcodeproj -scheme IconMator \
  -configuration Release -derivedDataPath .research/AppDerived \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
# BUILD SUCCEEDED
```

The `--disable-sandbox`, writable `HOME`, and outer-sandbox relaxation are
workarounds for this agent harness: SwiftPM and Xcode's SwiftPM integration invoke
a nested `sandbox-exec` that the workspace sandbox denies. They do not change the
compiled product. See [DEVELOPMENT.md](../DEVELOPMENT.md).

## Logs and local outputs

| Path | Contents |
| --- | --- |
| `Docs/Research/Logs/appearance-tests.txt` | Final tracked full test output (12 presentation + 26 core/integration tests) |
| `Docs/Research/Logs/appearance-debug-build.txt` | Final tracked Debug xcodebuild output |
| `Docs/Research/Logs/appearance-release-build.txt` | Final tracked Release xcodebuild output |
| `Docs/Research/Logs/appearance-conversions.txt` | Tracked Default/Dark/Mono CLI conversions and diagnostics |
| `.research/Appearances/FinalValidation/` | Local, ignored copies of the final validation evidence |
| `.research/Appearances/TrackedValidation/` | CLI outputs used for the tracked conversion log |
| `.research/Appearances/Implementation/` | Earlier CLI-produced Default/Dark/Mono ICNS and PNGs plus diagnostics |
| `.research/Appearances/SystemReferences/` | System Default/Dark/ClearLight/ClearDark 1024 references |
| `.research/Appearances/System/` | `.aqua` / `.darkAqua` extraction comparison |
| `.research/Appearances/Tools/` | Research-only probes and helpers (not production code) |
| `.research/AppDerived/Build/Products/Debug/IconMator.app` | Debug app build |
| `.research/AppDerived/Build/Products/Release/IconMator.app` | Release app build |
| `.research/home/` | Harness-local HOME used for SwiftPM/Xcode caches |
| `ReferenceInputs/Metadatics/Metadatics.icon` and `.png` | Private local fixture, ignored by Git |

Do not commit the private reference artwork or generated comparison images.

## Known issues and validation gaps

- No independent Finder Dark or Mono reference was available. Dark/Mono were
  compared against an appearance-specific system renderer. The research-only
  reference probe used the private `ISImageDescriptor` API; production uses only
  `ictool` and public `NSWorkspace`. This is an evidence gap, not a runtime
  dependency.
- Interactive visual acceptance, Finder custom-icon display, and multi-scale
  visual review were not performed. No GUI verification was performed, per the
  task restriction.
- Mono maps to `ClearLight` (untinted light clear). This is a product decision:
  the UI has one Mono control and a separate Dark control. `ClearDark` is verified
  but not exposed. If Mono should follow system light/dark, that requires a
  separate explicit option.
- Runtime support remains restricted to macOS 27.0.1/Xcode 27.1. The existing
  exact environment gate was intentionally not expanded for this feature.
- The Debug ad-hoc signature does not carry the Hardened Runtime flag even though
  the build setting is YES; Xcode emitted this behavior. Release does carry it.
  This is a signing/configuration observation, not an appearance regression.
- `tools` output now wraps the developer tools and `appearanceCapabilities`;
  consumers of the old flat JSON shape would need updating. This is documented.
- Capability probing checks that the Composer executable/version is readable; the
  actual rendering path is verified by the real integration matrix, not by every
  capability call.

## Exact next steps

1. Tracked validation logs are now in `Docs/Research/Logs/` and linked from
   [VALIDATION_REPORT.md](VALIDATION_REPORT.md). The implementation and
   documentation checkpoint is complete; only the final response remains.
2. If resuming implementation, the next product decision is whether to expose
   `ClearDark` separately. Do not change Mono's mapping without updating the
   research, UI copy, capability report and integration expectations.
3. Re-run the full matrix before any release claim:
   ```sh
   ICONMATOR_INTEGRATION=1 swift test --disable-sandbox --scratch-path .build/native
   ```
4. Re-run Debug and Release builds with the harness workarounds above.
5. Do not launch the application for inspection. Continue source-review and
   presentation-model validation only.

## Assumptions to preserve

- The existing compiled-asset backend and system extraction path remain the
  Default reference.
- `ClearLight` is the intended untinted Mono variant for this single-choice UI.
- The temporary legacy ICNS presentation is acceptable only because the system
  applies the same macOS canvas and shadow measured for Default; the temporary
  ICNS is never exported.
- All `ictool`/`NSWorkspace` behavior is measured on the stated macOS/Xcode
  combination only.
