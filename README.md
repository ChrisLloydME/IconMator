# IconMator

Native macOS Icon Composer → static ICNS utility, currently in rendering research. The production conversion and SwiftUI workflow are gated on comparison with a real Finder reference. The existing starter UI is not yet a converter.

Requirements: macOS 26+, full Xcode. Research performed on macOS 27.0.1 and Xcode 27.1. No network dependency or third-party packages.

Build the command-line research utility with `swift build`. Run `swift test` for non-GUI image-comparison tests. With the native SwiftPM build system, the executable is `.build/debug/iconmator` (or the chosen scratch path). `iconmator inspect image.png` reports full-canvas geometry; `iconmator compare reference.png candidate.png directory` writes metrics, a difference PNG, and a side-by-side PNG. Comparison normalizes to 8-bit sRGB and preserves original files.

See [RENDERING_RESEARCH.md](RENDERING_RESEARCH.md) for experimental evidence and outstanding gates. User-supplied references and temporary builds are intentionally Git-ignored.

The Xcode app retains the Release identifier `com.lloydME.IconMator`; Debug uses `com.lloydME.IconMator.beta`. The visible application name remains IconMator. The deployment target is macOS 26.
