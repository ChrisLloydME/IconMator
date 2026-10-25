# Licensing and third-party review

Reviewed on 2026-10-25. IconMator's original application code, conversion library,
CLI, tests and original documentation use the [MIT License](LICENSE), copyright
2026 Chris Lloyd. This does not relicense Apple's software/documentation, system
symbols, user-provided artwork or other third-party material.

## Application dependencies

The current Package.swift has no external package dependencies. The Xcode project
references only the local IconConversionCore package. No vendored source tree,
Git submodule, CocoaPods or Carthage dependency was found. The inspected Release
app contains no bundled third-party framework, and `otool -L` lists Apple system
frameworks and system Swift libraries.

| Component | How used | License / ownership |
| --- | --- | --- |
| IconConversionCore and IconMatorPresentation | Modules implemented in this repository | Project MIT license |
| Swift standard library/runtime | Supplied by the Swift/Xcode toolchain and macOS; no vendored source | [Apache 2.0 with Runtime Library Exception](https://github.com/swiftlang/swift/blob/main/LICENSE.txt); not relicensed by this project |
| Swift Testing | Toolchain test dependency, not a release-app dependency | [Apache 2.0 with Runtime Library Exception](https://github.com/swiftlang/swift-testing/blob/main/LICENSE.txt) |
| XCTest | Xcode test-target framework, not a release-app dependency | Apple's supplied SDK terms |
| SwiftUI, AppKit, Foundation, CoreGraphics, ImageIO, Observation, UniformTypeIdentifiers and Darwin APIs | System frameworks/libraries | Apple's supplied SDK/system terms; not project MIT code |
| SF Symbols referenced with systemName | Resolved through the system at runtime; no exported symbol artwork is bundled | Apple's system-symbol terms; not project MIT artwork |
| actool, clang, xcodebuild, xcrun, xcode-select, sw_vers and iconutil | Invoke the user's installed developer/system tools | Their supplied licenses; executables are not copied or distributed with IconMator |

The Swift Runtime Library Exception addresses compiler/runtime portions embedded
by compiling source. This project does not redistribute Swift toolchain source
or a separately downloaded Swift runtime. If future releases add or bundle other
components, review their exact versions and notices before distribution.

## Research references, not imported implementations

- [CodexBar's icon build script](https://github.com/steipete/CodexBar/blob/main/Scripts/build_icon.sh)
  was read as a research reference. No CodexBar source or script is included in
  IconMator; its fixed padding pipeline was not adopted. Its upstream project
  uses [MIT](https://github.com/steipete/CodexBar/blob/main/LICENSE).
- [Michael Tsai's margin discussion](https://mjtsai.com/blog/2025/10/02/how-to-export-a-mac-icon-file-with-the-proper-margins/)
  and Apple's documentation are cited research references, not dependencies.
- The ICNS encoder is implemented here from format experiments with Apple's
  output. No external ICNS library was copied or linked.

## Artwork and external documentation

`IconMator/AppIcon.icon` is the application icon supplied by the maintainer for
use as IconMator branding. Its artwork is excluded from the software MIT grant
unless the rights holder separately licenses it. The project compiles this
original Icon Composer document directly; it is distinct from the removed
third-party research examples.

Metadatics example PNG/ICNS files are not licensed under this project's MIT
license. They have been removed from the repository and its Git history at the
maintainer's request. Private reference inputs and regenerated conversion outputs
must remain outside the distributed source tree. Converting an image does not
change the underlying artwork's copyright, license or trademark rights.

The captured Apple actool manual has been removed from the repository and its
Git history. Read the installed documentation locally with `man actool` instead;
only original research commentary and tool diagnostics remain here.
Tool-generated diagnostic output and quoted external material retain any
applicable original rights. The project's own measurements and commentary are
MIT-licensed; no permission to relicense external materials is asserted.

## Release packaging

The macOS app includes LICENSE and this notice in Contents/Resources. When
packaging the standalone CLI or source, include these files as well. No unrelated example
artwork or Apple developer executables belong in the release archive. The
maintainer-supplied application icon is included as application branding.

Review scope: tracked files, package/project configuration, recorded implementation
provenance, and the current local Release bundle. This is a dependency/provenance
inventory, not a claim that all software supplied by macOS is MIT-licensed.

## Artwork-removal verification

The maintainer requested deletion of the Metadatics examples, including history.
The three tracked PNG/ICNS files and the copied Apple manual were removed from
every commit and tree-only snapshot reference. Filter backups and reflogs were expired and unreachable Git
objects pruned. Each removed artwork/manual blob ID was checked with `git cat-file` and was
no longer readable. All working files outside the explicitly removed paths were verified unchanged
during each rewrite. There was no configured remote, so no remote push was performed.
Original private inputs under ignored ReferenceInputs remain local and were not
modified or distributed. This does not claim removal of private files outside Git.
