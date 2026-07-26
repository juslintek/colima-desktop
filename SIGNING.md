# macOS Signing, Notarization & Sparkle Auto-Update

This document is the authoritative reference for shipping a trusted, auto-updating macOS
build of Colima Desktop. It covers three independent credential sets:

1. **Sparkle EdDSA appcast key** — already generated and wired (no Apple account needed).
2. **Developer ID code signing** — requires Apple Developer Program membership.
3. **Notarization** — requires the same Apple membership.

Everything is **credential-gated and honest**: when a credential is absent the release
pipeline still builds, but the artifact is built **UNSIGNED**, labelled
`UNSIGNED — signing credential <NAME> absent` in `release-manifest.json`, and the
notarize/appcast steps are **skipped with a clear message** — never faked. No private key
is ever committed to the repository.

---

## 1. Sparkle auto-update key (DONE — real, non-placeholder)

Sparkle verifies every downloaded update against an **Ed25519 public key** compiled into
the app. A **real** key pair has already been generated for this repository:

| Item | Value / location |
|------|------------------|
| **Public key** (`SUPublicEDKey`) | `s9mMrmm8Gydc6gn5JWOY2586TROs/PTaM6wm71s5Wcc=` |
| Where the public key is wired | `packaging/Info.plist` → `SUPublicEDKey` (committed — public is safe) |
| Feed URL (`SUFeedURL`) | `https://raw.githubusercontent.com/juslintek/colima-desktop/main/appcast.xml` |
| **Private key** (never committed) | macOS **login keychain** — generic password `Private key for signing Sparkle updates` (account `ed25519`, service `https://sparkle-project.org`) |
| Private key in CI | GitHub repo secret **`SPARKLE_PRIVATE_KEY`** (must be the export of the keychain key above) |

The public key decodes to exactly 32 bytes (a valid Ed25519 key) and its matching private
key is confirmed present in the login keychain. This is **not** the old
`REPLACE_WITH_ED25519_PUBLIC_KEY` placeholder.

### Regenerating / rotating the key (only if ever needed)

`generate_keys` is **idempotent** — it never overwrites an existing key, so re-running is
safe and will just print the current public key:

```bash
make app            # once, to resolve the Sparkle package (provides generate_keys)
make sparkle-keys   # prints the public key; private key stays in the login keychain
```

To **rotate** (invalidates the old key — only for a compromised key, and it breaks
auto-update from builds shipped with the old key), delete the keychain item first, then
re-run `make sparkle-keys`, and paste the new public key into `packaging/Info.plist`.

### Wiring the private key into CI (one-time, to enable signed appcasts)

Export the private key from the keychain and store it as the `SPARKLE_PRIVATE_KEY` repo
secret. **Never commit the exported file** — delete it immediately after.

```bash
BIN=$(find build -path '*artifacts/sparkle/Sparkle/bin' -type d | head -1)
"$BIN/generate_keys" -x sparkle_private_key.pem      # export the PRIVATE key
gh secret set SPARKLE_PRIVATE_KEY < sparkle_private_key.pem
rm -f sparkle_private_key.pem                        # do NOT leave this on disk
```

The appcast is produced by `scripts/sparkle-appcast.sh`, which signs each DMG with the
keychain key locally, or with `SPARKLE_PRIVATE_KEY` (read from stdin) in CI. Clients verify
those signatures against the committed `SUPublicEDKey`, so the CI secret **must** be the
export of the same key.

---

## 2. Developer ID signing (requires Apple Developer Program)

macOS Gatekeeper trusts apps signed with a **Developer ID Application** certificate. This
requires a paid **Apple Developer Program** membership (needed to issue the certificate).
Colima Desktop ships via **Developer ID + notarization** (not the Mac App Store — the app
spawns `colima`/`docker`/`brew` and uses `~/.colima` sockets, which the App Store sandbox
forbids).

### Required GitHub repo secrets

| Secret | What it is |
|--------|------------|
| `MACOS_CERTIFICATE_P12` | base64 of the exported Developer ID Application cert + private key (`.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | password protecting that `.p12` |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `KEYCHAIN_PASSWORD` | any strong string; unlocks the temporary CI keychain |

### One-time local export (to create `MACOS_CERTIFICATE_P12`)

1. In **Xcode → Settings → Accounts**, or the [Apple Developer portal](https://developer.apple.com/account/resources/certificates/list), create a **Developer ID Application** certificate.
2. In **Keychain Access**, select the cert **and** its private key → right-click → **Export 2 items…** → save as `cert.p12` with a password.
3. Encode and store the secrets:

```bash
base64 -i cert.p12 | gh secret set MACOS_CERTIFICATE_P12
gh secret set MACOS_CERTIFICATE_PASSWORD      # the .p12 password
gh secret set MACOS_SIGN_IDENTITY             # "Developer ID Application: Your Name (TEAMID)"
gh secret set KEYCHAIN_PASSWORD               # any strong random string
rm -f cert.p12
```

### Signing locally

`scripts/package.sh` is credential-gated: with no identity it builds an **UNSIGNED** (ad-hoc)
DMG; with an identity it signs with the hardened runtime + entitlements.

```bash
# Unsigned (pipeline/local verification — Gatekeeper will block):
scripts/package.sh

# Signed (Developer ID present in your keychain):
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/package.sh
```

---

## 3. Notarization (requires Apple Developer Program)

After signing, Apple must **notarize** the DMG so Gatekeeper opens it without a warning.

### Required GitHub repo secrets

| Secret | What it is |
|--------|------------|
| `NOTARY_APPLE_ID` | the Apple ID email used for notarization |
| `NOTARY_TEAM_ID` | your 10-char Apple Team ID |
| `NOTARY_PASSWORD` | an **app-specific password** (create at [account.apple.com](https://account.apple.com) → App-Specific Passwords) — not your Apple ID password |

### Notarizing locally

```bash
# Store a notarytool profile once:
xcrun notarytool store-credentials ColimaDesktopNotary \
  --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"

# Sign + notarize + staple in one shot:
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=ColimaDesktopNotary NOTARIZE=1 scripts/package.sh
```

`package.sh` submits with `notarytool --wait`, then `stapler staple`s and validates the ticket.

---

## 4. How the release pipeline uses these

`.github/workflows/release.yml` (tag-triggered, `v*`) is gated on the release-candidate
workflow being green, then per component:

- **macOS** — imports `MACOS_CERTIFICATE_P12` into a temporary keychain **only when
  `MACOS_CERTIFICATE_P12` and `MACOS_SIGN_IDENTITY` are both set** (`HAS_SIGNING`); configures
  notarization **only when `NOTARY_APPLE_ID` is set** (`HAS_NOTARY`); runs `scripts/package.sh`
  with `NOTARIZE=1` only when both are present. Otherwise the DMG is UNSIGNED-labelled and
  notarization is skipped.
- **Sparkle appcast** — the publish job runs `scripts/sparkle-appcast.sh` **only when
  `SPARKLE_PRIVATE_KEY` is set** (`HAS_SPARKLE`), signs the DMGs, and commits `appcast.xml` to
  `main` (served at `SUFeedURL`).

### Enablement checklist for a fully-signed, auto-updating v1 release

- [ ] Apple Developer Program membership active.
- [ ] `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGN_IDENTITY`, `KEYCHAIN_PASSWORD` set.
- [ ] `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` (app-specific) set.
- [ ] `SPARKLE_PRIVATE_KEY` set to the export of the keychain key whose public half is `s9mMrmm8Gydc6gn5JWOY2586TROs/PTaM6wm71s5Wcc=`.
- [ ] Push a `vX.Y.Z` tag → the pipeline signs, notarizes, publishes assets + checksums, and commits a signed appcast.

Until the Apple secrets exist, releases are produced **UNSIGNED but honestly labelled**; the
Sparkle key is already real, so auto-update signing works the moment `SPARKLE_PRIVATE_KEY` is set.
