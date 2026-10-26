# IconMator Documentation

Detailed project documentation lives here. The repository root retains only the
project [README](../README.md) and [LICENSE](../LICENSE) as public entry points.

## Guides

| Document | Contents |
| --- | --- |
| [Development](DEVELOPMENT.md) | Requirements, app/CLI builds, tool selection, signing and testing |
| [Architecture](ARCHITECTURE.md) | Rendering pipeline, components, file safety, cancellation and UI |
| [Third-party notices](THIRD_PARTY_NOTICES.md) | MIT scope, dependencies, artwork rights and license review |

## Research and Validation

| Document | Contents |
| --- | --- |
| [Rendering research](Research/RENDERING_RESEARCH.md) | Actual tools, evaluated approaches, measurements and backend selection |
| [Appearance research](Research/APPEARANCE_RESEARCH.md) | Verified Default/Dark/Mono renditions, geometry and color measurements |
| [Validation report](Research/VALIDATION_REPORT.md) | Build/test results, reference differences and unverified acceptance items |
| [Tool/build logs](Research/Logs/) | Recorded compiler, renderer, signature and test output |
| [Comparison metrics](Research/Comparisons/) | Whole-canvas image-comparison JSON reports |

Historical shell commands preserve the paths used when the experiments ran.
Retained evidence has since moved from `Research/` to `Docs/Research/`; new
comparison reports should use the current directory. Original tool output is
kept unchanged rather than rewritten to resemble a new execution.

## Images

[Images/](Images/) contains project-branding assets for documentation. The README
icon is exported from the maintainer-supplied `IconMator/AppIcon.icon` using the
same conversion pipeline as the app. It is not a screenshot or a research sample.

Private reference artwork, generated comparison PNGs and temporary builds are not
distributed. See the validation report for reproducing checks with authorized
local fixtures; no Apple manual or executable is vendored here.
