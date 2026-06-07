# Distributing Colima Desktop

## Can it ship on the Mac App Store? — No (by design)

**The Mac App Store is not a viable channel for this app**, and that is a fundamental
constraint, not a configuration gap:

- App Store apps **must** enable the **App Sandbox**.
- Colima Desktop's core function is to **launch external executables** (`colima`, `docker`,
  `brew`, `kubectl`) via `Process()` and to talk to **Unix sockets under `~/.colima/`**.
- The App Sandbox **forbids** executing non-bundled binaries and accessing files/sockets
  outside the container. Apple also rejects apps that **download/install other software**
  (our install prompt runs `brew install colima docker`).

There is no entitlement that re-enables this inside the sandbox. Making it "App Store legal"
would mean removing the very thing the app does. This is why every comparable tool —
**Docker Desktop, OrbStack, Podman Desktop, Lima** — ships **outside** the App Store via a
signed, notarized direct download.

**Verdict:** distribute as a **Developer ID-signed, notarized `.app` in a `.dmg`** (done below).

## App icon

`scripts/make-icon.sh` generates the icon (original isometric-cube artwork on a teal→blue
squircle — no third-party marks) headlessly via CoreGraphics, producing
`Sources/Assets.xcassets/AppIcon.appiconset/` (10 macOS sizes) and a standalone
`packaging/AppIcon.icns`. `project.yml` sets `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`, so
the built `.app` carries `CFBundleIconName=AppIcon` (verified) and shows in Finder/Dock. The
DMG also gets the icon as its volume icon (best-effort). Regenerate the artwork with
`scripts/make-icon.sh` then rebuild.

## What's in the repo

| File | Purpose |
|------|---------|
| `packaging/ColimaDesktop.entitlements` | Hardened-Runtime entitlements, **no** App Sandbox |
| `scripts/package.sh` | Build Release -> (sign) -> DMG -> (notarize + staple) |
| `make package-dmg` | Unsigned DMG (pipeline proof) |
| `make release` | Signed + (optionally) notarized DMG |

Output: `dist/Colima Desktop.dmg`. An **unsigned** DMG builds today and is verified
(`hdiutil verify` -> checksum VALID, ~6.3 MB) — Gatekeeper will block it until signed+notarized.

## Prerequisites for a shippable build

1. **Apple Developer Program** membership.
2. A **Developer ID Application** certificate in your login keychain
   (Xcode -> Settings -> Accounts -> Manage Certificates -> +).
3. A **notarytool** credential profile (one-time):
   ```bash
   xcrun notarytool store-credentials ColimaDesktopNotary \
     --apple-id "you@example.com" --team-id "TEAMID" \
     --password "app-specific-password"   # appleid.apple.com -> App-Specific Passwords
   ```

## Build commands

```bash
# 1) Local pipeline proof (unsigned):
make package-dmg

# 2) Signed + notarized release:
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="ColimaDesktopNotary" \
NOTARIZE=1 \
make release
```

The script signs deeply with `--options runtime --timestamp` and the entitlements above,
signs the DMG, submits to `notarytool --wait`, then `stapler staple`s the ticket so the app
opens offline without Gatekeeper prompts. Final `spctl --assess` confirms acceptance.

## Versioning (tag-driven)

Releases are versioned from **git tags** via `scripts/version.sh`:
- `CFBundleShortVersionString` (marketing) = latest `vX.Y.Z` tag, leading `v` stripped.
- `CFBundleVersion` (build) = `git rev-list --count HEAD` (monotonic, always increasing).

`scripts/package.sh` derives these and passes `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`
into the Release build, and names the artifact `dist/Colima Desktop-<version>.dmg`.
`project.yml` carries dev defaults (`0.0.0` / `1`).

**Cut a tagged release:**
```bash
git tag v1.2.0 && git push origin v1.2.0
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="ColimaDesktopNotary" NOTARIZE=1 make release
# -> dist/Colima Desktop-1.2.0.dmg, CFBundleShortVersionString=1.2.0
```
Override without a tag for a one-off: `VERSION=1.2.0 make release`.
Verified end-to-end: a `0.1.0` build produced `CFBundleShortVersionString=0.1.0`,
`CFBundleVersion=81`, `dist/Colima Desktop-0.1.0.dmg`.

## Gatekeeper / user experience

- Signed + notarized + stapled DMG -> double-click, drag to Applications, opens with no warning.
- Unsigned DMG -> "cannot be opened because the developer cannot be verified"; only for local QA.

## Troubleshooting

- `notarytool` rejects with "hardened runtime" errors -> ensure `ENABLE_HARDENED_RUNTIME=YES`
  (the script sets it) and that all nested binaries are signed (`--deep`).
- `spctl` rejects after notarize -> you forgot to `stapler staple` (the script does it when
  `NOTARIZE=1`).
- App launches but can't find `colima` -> that's runtime PATH, not signing; the app probes
  `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin` and offers to `brew install` if missing.

## Future option: a .pkg installer

A `.pkg` (productbuild, signed with a **Developer ID Installer** cert + notarized) is also
possible if you want a guided installer instead of drag-to-Applications. The DMG is the
lighter-weight standard for dev tools and is what's implemented here.
