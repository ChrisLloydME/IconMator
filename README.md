# IconMator

Native macOS Icon Composer → static ICNS utility. The conversion prototype compiles Apple assets, obtains the current Default appearance through public system icon rendering, and independently verifies every ICNS rendition. Rendering is numerically close to the supplied Finder reference, not pixel-identical; visual acceptance is still outstanding.

Requirements: macOS 26+, full Xcode. Research performed on macOS 27.0.1 and Xcode 27.1. No network dependency or third-party packages.

Build the command-line research utility with `swift build`. Run `swift test` for non-GUI image-comparison tests. With the native SwiftPM build system, the executable is `.build/debug/iconmator` (or the chosen scratch path). `iconmator inspect image.png` reports full-canvas geometry; `iconmator compare reference.png candidate.png directory` writes metrics, a difference PNG, and a side-by-side PNG. Comparison normalizes to 8-bit sRGB and preserves original files.

See [RENDERING_RESEARCH.md](RENDERING_RESEARCH.md) for experimental evidence and outstanding gates. User-supplied references and temporary builds are intentionally Git-ignored.

The Xcode app retains the Release identifier `com.lloydME.IconMator`; Debug uses `com.lloydME.IconMator.beta`. The visible application name remains IconMator. The deployment target is macOS 26.


CLI conversion: `iconmator convert input.icon output.icns --png`. Existing files are refused unless `--replace` is explicitly supplied. `iconmator package-png master.png output.icns` creates the reference ICNS from an existing 1024² RGBA PNG without changing the master. `iconmator tools` prints the discovered toolchain.

Run real-tool integration tests with `ICONMATOR_INTEGRATION=1 swift test`; these require the ignored `ReferenceInputs/Metadatics` fixture folder. Tests are skipped explicitly by default; no rendering output is mocked. In this environment SwiftPM's native build system was used (`--build-system native --scratch-path .build/native`), with executable `.build/native/debug/iconmator`.

Conversion currently permits only macOS 27.0.1 (26A434) and Xcode 27.1 (27A9275), the environment measured against the reference. Other combinations report an actionable unsupported-toolchain error. Dark, Mono, and OS-generation selection remain unavailable. No software is downloaded at runtime.
