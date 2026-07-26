# Signing, Packaging & Trust (R8 / tasks 13.1–13.3)

This document is the authoritative reference for how Colima Desktop's release
artifacts are **packaged, signed, and verified**, and for the **install + trust
behavior** on each platform (Requirement 12.3).

Signing is **credential-gated and honest** on every platform:

- When the platform's signing credential is present (as a repository secret),
  the artifact is signed **and the signature is verified** before the release is
  accepted.
- When the credential is **absent**, the artifact is built **UNSIGNED** and
  labelled exactly `UNSIGNED - signing credential <NAME> absent` in
  `release-manifest.json`. The build never fabricates a signature and never
  commits a private key or certificate.

The native Windows and Linux packaging runs on the platform's own CI runner
(`windows-latest` / `ubuntu-latest`) because WinUI 3 and GTK 4 cannot build on
the macOS verification host. On macOS the packaging scripts are validated
statically; the runners are authoritative for the produced binaries.

## Required signing credentials (repository secrets)

Each is optional. When absent, the matching artifact is UNSIGNED-but-labelled
and the release still completes (delivery of the signature is deferred, not the
release).

| Platform | What gets signed | Secret names |
|----------|------------------|--------------|
| macOS (app + dmg) | `.app`/`.dmg` Developer ID | `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGN_IDENTITY`, `KEYCHAIN_PASSWORD` |
| macOS notarization | notarized ticket stapled to `.dmg` | `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` |
| macOS auto-update | Sparkle appcast | `SPARKLE_PRIVATE_KEY` (Ed25519) |
| **Windows Authenticode** | launcher `.exe` (+ app `.dll`) | `WINDOWS_CERTIFICATE_PFX`, `WINDOWS_CERTIFICATE_PASSWORD` (+ optional `WINDOWS_TIMESTAMP_URL`) |
| **Linux GPG** | `.tar.gz` and `.deb` (detached `.asc`) | `LINUX_GPG_PRIVATE_KEY`, `LINUX_GPG_PASSPHRASE` (+ optional `LINUX_GPG_KEY_ID`) |

`WINDOWS_CERTIFICATE_PFX` and `LINUX_GPG_PRIVATE_KEY` are the base64/armored key
material; store them **only** as encrypted repository secrets, never in the repo.

## Windows (WinUI 3)

**Artifact:** `ColimaDesktop-<version>-windows-x64.zip` — a self-contained
`dotnet publish` (win-x64) with the product/file/assembly version stamped from
the git tag (`-p:Version -p:FileVersion -p:AssemblyVersion`). Built by
`scripts/windows/package-windows.ps1` on the `windows-latest` runner.

**Signing:** when `WINDOWS_CERTIFICATE_PFX` is present, the script discovers
`signtool.exe` from the installed Windows SDK (it is not on `PATH` by default),
signs the launcher `ColimaDesktop.Windows.exe` and the app's managed
`ColimaDesktop.Windows.dll` with SHA-256 + an RFC-3161 timestamp, then
**verifies** each with `signtool verify /pa`. The `.zip` container is not itself
Authenticode-signable; its integrity is covered by the SHA-256 recorded in the
sidecar and the aggregate `SHA256SUMS.txt`.

**Install:** download the `.zip`, extract it, and run `ColimaDesktop.Windows.exe`.
The Windows frontend connects to the daemon over loopback TCP.

**Trust behavior:**
- *Signed* build → the signed `.exe` shows the verified publisher in the
  SmartScreen prompt and in the file's Properties → Digital Signatures tab.
- *Unsigned* build (credential absent) → Windows SmartScreen shows an
  "unknown publisher" warning; choose **More info → Run anyway** to launch.
  Verify integrity first via the checksum (below).

**Verify a download:**
```powershell
# integrity
Get-FileHash -Algorithm SHA256 ColimaDesktop-<version>-windows-x64.zip
# ...compare against SHA256SUMS.txt (or release-manifest.json)
# signature (after extracting)
signtool verify /pa ColimaDesktop.Windows.exe
```

## Linux (GTK 4)

**Artifacts:** built by `scripts/linux/package-linux.sh` on the `ubuntu-latest`
runner, version-stamped from the git tag:
- `colima-desktop-<version>-linux-<arch>.tar.gz` — a relocatable tree
  (`colima-desktop` binary + `VERSION` + `.desktop` entry + README).
- `colima-desktop_<version>_<debarch>.deb` — a Debian package installing to
  `/usr/bin/colima-desktop` with a desktop entry (`--deb`; depends on
  `libgtk-4-1`, `libadwaita-1-0`).

**Signing:** when `LINUX_GPG_PRIVATE_KEY` is present, each artifact gets a
detached, armored GPG signature (`<artifact>.asc`) which is then **verified**
(`gpg --verify`) before the run is accepted.

**Install:**
```bash
# tar.gz (no root required)
tar xzf colima-desktop-<version>-linux-<arch>.tar.gz
./colima-desktop-<version>-linux-<arch>/colima-desktop

# .deb (system-wide)
sudo apt install ./colima-desktop_<version>_<debarch>.deb   # resolves GTK deps
# or: sudo dpkg -i colima-desktop_<version>_<debarch>.deb && sudo apt -f install
```

**Trust behavior:**
- *Signed* build → verify the detached signature against the maintainer's public
  key before installing. The `.deb`'s `.asc` provides the same file-level trust
  (this is detached-signature trust, distinct from an apt-repository `Release`
  signature).
- *Unsigned* build (key absent) → the artifact is labelled `UNSIGNED` in
  `release-manifest.json`; verify integrity by checksum until the key is set.

**Verify a download:**
```bash
# integrity
sha256sum -c SHA256SUMS.txt
# signature (import the maintainer public key first)
gpg --verify colima-desktop-<version>-linux-<arch>.tar.gz.asc \
             colima-desktop-<version>-linux-<arch>.tar.gz
gpg --verify colima-desktop_<version>_<debarch>.deb.asc \
             colima-desktop_<version>_<debarch>.deb
```

## Checksums manifest

`scripts/release/checksums.sh` writes, next to the artifacts:

- `SHA256SUMS.txt` — `<sha256>  <name>` lines (verify with
  `shasum -a 256 -c SHA256SUMS.txt` / `sha256sum -c SHA256SUMS.txt`).
- `release-manifest.json` — per-artifact `{name, size, sha256, component,
  signed, signing_status, required_credentials}` + a signing summary + the union
  of every artifact's required signing-credential names. Each packaging script
  also records the artifact's `sha256` and honest `signing_status` in a
  `<artifact>.meta.json` sidecar that the manifest merges.

## Local validation on the macOS host

The Windows/Linux native packaging is **CI-authoritative** (it runs on
`windows-latest` / `ubuntu-latest`). On the macOS verification host:

- `scripts/linux/package-linux.sh` can be exercised in a degraded form with
  `--dry-run` (packages a placeholder binary so the tar.gz/.deb/signing/checksum
  logic runs without `cargo`/GTK); real binaries come from the `linux-gtk4`
  runner.
- `scripts/windows/package-windows.ps1` is validated on the `windows-winui`
  runner (PowerShell + the Windows SDK + `dotnet` are Windows-only).
