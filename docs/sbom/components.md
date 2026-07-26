# Software Bill of Materials — Component Inventory

Machine-readable CycloneDX 1.5 SBOMs live in `docs/sbom/cyclonedx/`.
Regenerate with `make sbom` (see `scripts/sbom.sh`). Output is byte-stable.

| Component | Ecosystem | Source manifest | Dependencies |
|-----------|-----------|-----------------|-------------:|
| colima-daemon (Go) | Go modules | `daemon/go.mod` | 22 |
| colima-tui (Go) | Go modules | `tui/go.mod` | 29 |
| colima-desktop-linux (Rust/GTK4) | Rust crates | `linux/Cargo.lock` | 239 |
| ColimaDesktop.Windows (.NET/WinUI3) | NuGet | `windows/ColimaDesktop.Windows.csproj` | 7 |
| ColimaDesktop (Swift/SwiftUI) | Swift SPM | `Package.resolved` | 5 |
| **Aggregate (unique)** | all | — | **294** |

## CycloneDX files

- `docs/sbom/cyclonedx/daemon.cdx.json` — colima-daemon (Go)
- `docs/sbom/cyclonedx/tui.cdx.json` — colima-tui (Go)
- `docs/sbom/cyclonedx/linux.cdx.json` — colima-desktop-linux (Rust/GTK4)
- `docs/sbom/cyclonedx/windows.cdx.json` — ColimaDesktop.Windows (.NET/WinUI3)
- `docs/sbom/cyclonedx/macos.cdx.json` — ColimaDesktop (Swift/SwiftUI)
- `docs/sbom/cyclonedx/colima-desktop.aggregate.cdx.json` — merged, de-duplicated

