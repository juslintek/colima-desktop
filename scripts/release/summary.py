#!/usr/bin/env python3
"""Render a Markdown release summary from dist/release-manifest.json.

Used by .github/workflows/release.yml (task 13.1) to write an honest
artifact + signing-status table (and the required-credential names for a
fully-signed release) into the GitHub step summary. Reads only the manifest
produced by scripts/release/checksums.sh — never a secret.

Usage: python3 scripts/release/summary.py [path-to-release-manifest.json]
"""
import json
import sys


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "dist/release-manifest.json"
    try:
        manifest = json.load(open(path))
    except Exception as exc:  # noqa: BLE001 - summary must never crash the release
        print(f"_release manifest unavailable ({exc})_")
        return 0

    summary = manifest.get("signing_summary", {})
    print(f"## Release v{manifest.get('version', '?')}")
    print()
    print(
        f"{summary.get('signed', 0)} signed / "
        f"{summary.get('unsigned', 0)} unsigned / "
        f"{summary.get('total', 0)} total artifacts"
    )
    print()
    print("| artifact | component | signed | status |")
    print("|----------|-----------|--------|--------|")
    for a in manifest.get("artifacts", []):
        print(
            f"| {a.get('name')} | {a.get('component')} | "
            f"{a.get('signed')} | {a.get('signing_status')} |"
        )

    req = manifest.get("required_credentials", [])
    print()
    if req:
        print(
            "**Credentials required for a fully-signed release:** "
            + ", ".join(f"`{c}`" for c in req)
        )
    else:
        print("All artifacts signed — no signing credentials missing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
