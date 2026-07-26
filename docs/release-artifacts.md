# Release Artifacts & Signing (R8 / task 13.1)

When a version tag `vX.Y.Z` is pushed, `.github/workflows/release.yml` builds
**versioned, packaged artifacts for every shipped component**, checksums them,
and publishes a GitHub Release. Signing is **credential-gated**: present
credentials sign the artifact; absent credentials produce an **UNSIGNED**
artifact that is labelled honestly (never a faked signature).

The release pipeline is **gated on the release-candidate gate**
(`.github/workflows/release-candidate.yml`, task 12.5): the build/publish jobs
`needs:` an `rc-gate` job that reuses the RC workflow, so a release cannot be cut
unless the 9 `frontends.yml` jobs + `test.yml` + `verify.sh` + security + perf +
a11y gates are all GREEN.

## Single source of version truth

`scripts/version.sh` derives the version from the git tag and every component
reads it, so the version can never drift:

| Component | Stamp mechanism | Field set |
|-----------|-----------------|-----------|
| macOS app | `xcodebuild MARKETING_VERSION=… CURRENT_PROJECT_VERSION=…` (project has `GENERATE_INFOPLIST_FILE`) | `CFBundleShortVersionString` / `CFBundleVersion` |
| Go daemon & TUI | `go build -ldflags "-X main.version=… -X main.commit=… -X main.date=…"` (build-time injection; no source edit) | `--version` output (once the owner adds `var version`) |
| Windows | `dotnet publish -p:Version=… -p:FileVersion=… -p:AssemblyVersion=…` | product / file / assembly version |
| Linux | package name + bundled `VERSION` + `.desktop` `Version=` + manifest | package version |

```
scripts/version.sh            # MARKETING_VERSION=… / CURRENT_PROJECT_VERSION=… (eval)
scripts/version.sh marketing  # 1.0.0
scripts/version.sh json       # {"marketing":"1.0.0","build":"143","tag":"v1.0.0","commit":"…"}
```

> Note: the Go daemon/TUI ldflags target the conventional `main.version` symbol.
> The stamp is wired and correct today; the `--version` string surfaces once the
> daemon/TUI owner adds a one-line `var version string` + a `--version` printer
> (a minimal coordination point — the release pipeline does not edit their source).

## Artifact matrix

| Component | Runner | Artifact(s) | Built by |
|-----------|--------|-------------|----------|
| macOS | `macos-15` | `Colima Desktop-<v>.dmg`, `ColimaDesktop-<v>-macos.app.zip`, `colima-daemon-<v>-macos-universal`, `colima-tui-<v>-macos-universal` | `scripts/package.sh` + `scripts/package-go.sh` |
| Windows | `windows-latest` | `ColimaDesktop-<v>-windows-x64.zip` (Authenticode-signed `.exe`/`.dll` inside) | `scripts/windows/package-windows.ps1` |
| Linux | `ubuntu-latest` | `colima-desktop-<v>-linux-<arch>.tar.gz` + `colima-desktop_<v>_<debarch>.deb` (+ detached `.asc`) | `scripts/linux/package-linux.sh --deb` |
| SBOM | `macos-15` | `colima-desktop-<v>-sbom.tar.gz` | `scripts/sbom.sh` |
| Checksums | `macos-15` | `SHA256SUMS.txt`, `release-manifest.json` | `scripts/release/checksums.sh` |

The macOS `.dmg` (+ daemon/TUI binaries) and the full checksums manifest can also
be produced locally:

```
make package-dmg          # unsigned locally (Developer ID absent) — pipeline proof
make checksums            # regenerate SHA256SUMS.txt + release-manifest.json
SIGN_IDENTITY="Developer ID Application: … (TEAMID)" make package-dmg   # signed
```

## Checksums manifest

`scripts/release/checksums.sh` writes, next to the artifacts:

- **`SHA256SUMS.txt`** — `<sha256>  <name>` lines (verify with `shasum -a 256 -c SHA256SUMS.txt`).
- **`release-manifest.json`** — per-artifact `{name, size_bytes, sha256, component, signed, signing_status, required_credentials}` plus a `signing_summary` and the union of every artifact's required signing-credential names.

## Signing credentials (required for a fully-signed release)

Add these as **repository secrets**. Each is optional; when absent the matching
artifact is built UNSIGNED and labelled `UNSIGNED — signing credential <NAME>
absent`, and the notarize/publish step is skipped with a clear message.

| Channel | Secret names |
|---------|--------------|
| macOS Developer ID (app + dmg) | `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGN_IDENTITY`, `KEYCHAIN_PASSWORD` |
| macOS notarization | `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` |
| Sparkle auto-update | `SPARKLE_PRIVATE_KEY` (Ed25519) |
| Windows Authenticode | `WINDOWS_CERTIFICATE_PFX`, `WINDOWS_CERTIFICATE_PASSWORD` (+ optional `WINDOWS_TIMESTAMP_URL`) |
| Linux GPG | `LINUX_GPG_PRIVATE_KEY`, `LINUX_GPG_PASSPHRASE` (+ optional `LINUX_GPG_KEY_ID`) |

The pipeline is correct and **ready to sign the moment these secrets are
configured** — no code change is needed to enable signing. Task 13.1 provided
the credential-gated wiring and honest unsigned fallback; **task 13.3 completed
and hardened the Windows + Linux signing/packaging**: the Windows script now
discovers `signtool.exe` from the Windows SDK (it is not on `PATH`) and
**verifies** the Authenticode signature after applying it; the Linux script adds
an opt-in `.deb` alongside the `.tar.gz`, **verifies** each GPG signature, and
can be exercised locally with `--dry-run`. Both record the artifact `sha256` and
an honest `signing_status` in their `.meta.json` sidecar.

See **[SIGNING.md](SIGNING.md)** for the per-platform **install and trust
behavior** (Requirement 12.3) and the exact download-verification commands.
