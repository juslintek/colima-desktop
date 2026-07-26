#!/usr/bin/env python3
"""Deterministic SBOM generator for the Colima Desktop multi-language repo (task 12.2, R7 / Requirement 11.3).

Produces a CycloneDX 1.5 SBOM per component plus an aggregated SBOM, from the
committed dependency manifests / lockfiles — no network, byte-stable output:

  - Go daemon   -> daemon/go.mod            (module requirement graph, direct + indirect)
  - Go TUI      -> tui/go.mod
  - Rust Linux  -> linux/Cargo.lock         (fully-resolved [[package]] set)
  - .NET Windows-> windows/ColimaDesktop.Windows.csproj (direct PackageReference)
                    + optional dotnet-list JSON for transitive closure
  - Swift macOS -> Package.resolved         (pinned SPM dependency graph)

This is the "generate a component+version inventory from the lockfiles
deterministically" path from the task: `syft` is not installed on this host, so
we emit a valid CycloneDX 1.5 document directly. If `syft` is present the wrapper
script (scripts/sbom.sh) uses it instead and this generator is the fallback.

Determinism: components are sorted by purl; NO wall-clock timestamp or random
serialNumber is embedded by default (matches the repo's Property-9 idempotence
ethos — see scripts/gen-truth-table.py). Pass --timestamp to embed one.

Usage:
    python3 scripts/sbom_gen.py --root <repo-root> --out-dir docs/sbom \
        [--dotnet-json <windows-transitive.json>] [--timestamp]

Exit code 0 on success; non-zero on a hard failure (never on a merely-absent
optional input — a missing manifest yields an empty, clearly-labelled component).
"""

import argparse
import json
import os
import re
import sys
import tomllib
import xml.etree.ElementTree as ET

CDX_SPEC_VERSION = "1.5"
GENERATOR_NAME = "colima-desktop-sbom-gen"
GENERATOR_VERSION = "1.0.0"

# ---------------------------------------------------------------------------
# Component model
# ---------------------------------------------------------------------------


class Dep:
    """One resolved dependency (a CycloneDX `library` component)."""

    __slots__ = ("name", "version", "purl", "scope", "ecosystem")

    def __init__(self, name, version, purl, ecosystem, scope="required"):
        self.name = name
        self.version = version
        self.purl = purl
        self.ecosystem = ecosystem
        self.scope = scope

    def key(self):
        return (self.purl, self.name, self.version)

    def to_cdx(self):
        comp = {
            "type": "library",
            "name": self.name,
            "version": self.version,
            "purl": self.purl,
        }
        if self.scope and self.scope != "required":
            comp["scope"] = self.scope
        return comp


def _dedupe_sort(deps):
    """Remove exact duplicates and sort deterministically by purl."""
    seen = {}
    for d in deps:
        seen[d.key()] = d
    return [seen[k] for k in sorted(seen.keys())]


# ---------------------------------------------------------------------------
# Go (go.mod) — module requirement graph, direct + indirect
# ---------------------------------------------------------------------------

_GO_REQUIRE_LINE = re.compile(r'^\s*([^\s]+)\s+(v[^\s]+?)(?:\s+//\s*indirect)?\s*$')


def parse_go_mod(path):
    """Return (main_module_name, [Dep]) from a go.mod file.

    Parses both the single-line `require x v1` form and the `require ( ... )`
    block. Indirect deps are included (they ship in the built binary)."""
    if not os.path.isfile(path):
        return None, []
    main = None
    deps = []
    in_block = False
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if stripped.startswith("//") or not stripped:
                continue
            if main is None and stripped.startswith("module "):
                main = stripped.split(None, 1)[1].strip()
                continue
            if stripped.startswith("go ") and not in_block:
                continue
            if stripped.startswith("require (") or stripped == "require (":
                in_block = True
                continue
            if in_block and stripped == ")":
                in_block = False
                continue
            # single-line require
            if stripped.startswith("require ") and not in_block:
                stripped = stripped[len("require "):].strip()
            elif not in_block:
                # skip replace/exclude/retract/toolchain lines outside require
                continue
            m = _GO_REQUIRE_LINE.match(stripped)
            if not m:
                continue
            name, version = m.group(1), m.group(2)
            purl = "pkg:golang/%s@%s" % (name, version)
            deps.append(Dep(name, version, purl, "go"))
    return main, _dedupe_sort(deps)


# ---------------------------------------------------------------------------
# Rust (Cargo.lock) — fully-resolved package set
# ---------------------------------------------------------------------------


def parse_cargo_lock(path, crate_name=None):
    """Return (main_crate_name, [Dep]) from a Cargo.lock (v3) file.

    The root workspace crate (no `source`, matching crate_name) is treated as the
    main component and excluded from the dependency list."""
    if not os.path.isfile(path):
        return None, []
    with open(path, "rb") as fh:
        data = tomllib.load(fh)
    main = None
    deps = []
    for pkg in data.get("package", []):
        name = pkg.get("name")
        version = pkg.get("version", "")
        source = pkg.get("source")
        if source is None and (crate_name is None or name == crate_name):
            # local/workspace crate (the component itself)
            main = "%s@%s" % (name, version) if version else name
            continue
        purl = "pkg:cargo/%s@%s" % (name, version)
        deps.append(Dep(name, version, purl, "rust"))
    return main, _dedupe_sort(deps)


# ---------------------------------------------------------------------------
# .NET (csproj direct + optional dotnet-list transitive JSON)
# ---------------------------------------------------------------------------


def parse_csproj(path):
    """Return [Dep] of direct PackageReference entries from a .csproj."""
    if not os.path.isfile(path):
        return []
    deps = []
    try:
        tree = ET.parse(path)
    except ET.ParseError:
        return []
    root = tree.getroot()

    def localname(tag):
        return tag.rsplit("}", 1)[-1]

    for elem in root.iter():
        if localname(elem.tag) != "PackageReference":
            continue
        name = elem.get("Include") or elem.get("Update")
        version = elem.get("Version")
        if not name:
            continue
        if version is None:
            # Version may be a child element
            for child in elem:
                if localname(child.tag) == "Version":
                    version = (child.text or "").strip()
                    break
        version = version or ""
        purl = "pkg:nuget/%s@%s" % (name, version)
        deps.append(Dep(name, version, purl, "dotnet"))
    return _dedupe_sort(deps)


def parse_dotnet_list_json(path):
    """Return [Dep] from `dotnet list package --include-transitive --format json`."""
    if not path or not os.path.isfile(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (json.JSONDecodeError, OSError):
        return []
    deps = []
    for project in data.get("projects", []):
        for framework in project.get("frameworks", []):
            for kind, scope in (("topLevelPackages", "required"),
                                ("transitivePackages", "required")):
                for pkg in framework.get(kind, []):
                    name = pkg.get("id")
                    version = pkg.get("resolvedVersion") or pkg.get("requestedVersion") or ""
                    if not name:
                        continue
                    purl = "pkg:nuget/%s@%s" % (name, version)
                    deps.append(Dep(name, version, purl, "dotnet"))
    return _dedupe_sort(deps)


# ---------------------------------------------------------------------------
# Swift (Package.resolved) — pinned SPM dependency graph
# ---------------------------------------------------------------------------


def parse_package_resolved(path):
    """Return [Dep] from a Package.resolved (v2/v3 `pins`) file."""
    if not os.path.isfile(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (json.JSONDecodeError, OSError):
        return []
    deps = []
    pins = data.get("pins", [])
    for pin in pins:
        identity = pin.get("identity", "")
        location = pin.get("location", "")
        state = pin.get("state", {})
        version = state.get("version") or state.get("revision") or ""
        # Build a purl from the git location host+path when possible.
        loc = re.sub(r"^https?://", "", location)
        loc = re.sub(r"\.git$", "", loc)
        loc = loc.strip("/")
        if loc:
            purl = "pkg:swift/%s@%s" % (loc, version)
        else:
            purl = "pkg:swift/%s@%s" % (identity, version)
        deps.append(Dep(identity, version, purl, "swift", scope="optional"))
    return _dedupe_sort(deps)


# ---------------------------------------------------------------------------
# CycloneDX emission
# ---------------------------------------------------------------------------


def build_bom(component_name, component_version, component_type, deps, timestamp=None):
    metadata = {
        "tools": [
            {
                "vendor": "colima-desktop",
                "name": GENERATOR_NAME,
                "version": GENERATOR_VERSION,
            }
        ],
        "component": {
            "type": component_type,
            "name": component_name,
            "version": component_version or "0.0.0",
        },
    }
    if timestamp:
        metadata["timestamp"] = timestamp
    return {
        "bomFormat": "CycloneDX",
        "specVersion": CDX_SPEC_VERSION,
        "version": 1,
        "metadata": metadata,
        "components": [d.to_cdx() for d in deps],
    }


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=2, sort_keys=False)
        fh.write("\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv=None):
    ap = argparse.ArgumentParser(description="Deterministic CycloneDX SBOM generator")
    ap.add_argument("--root", default=".", help="repo root")
    ap.add_argument("--out-dir", default="docs/sbom", help="output dir (repo-relative)")
    ap.add_argument("--dotnet-json", default=None,
                    help="optional dotnet list package --format json for transitive .NET deps")
    ap.add_argument("--timestamp", default=None,
                    help="optional ISO-8601 timestamp to embed (default: omitted for reproducibility)")
    args = ap.parse_args(argv)

    root = os.path.abspath(args.root)
    out_dir = os.path.join(root, args.out_dir)
    cdx_dir = os.path.join(out_dir, "cyclonedx")

    # --- parse each ecosystem ---
    daemon_main, daemon_deps = parse_go_mod(os.path.join(root, "daemon", "go.mod"))
    tui_main, tui_deps = parse_go_mod(os.path.join(root, "tui", "go.mod"))
    linux_main, linux_deps = parse_cargo_lock(
        os.path.join(root, "linux", "Cargo.lock"), crate_name="colima-desktop-linux")

    win_csproj = os.path.join(root, "windows", "ColimaDesktop.Windows.csproj")
    win_direct = parse_csproj(win_csproj)
    win_transitive = parse_dotnet_list_json(args.dotnet_json)
    win_deps = _dedupe_sort(win_direct + win_transitive)

    swift_deps = parse_package_resolved(os.path.join(root, "Package.resolved"))

    components = [
        # (key, display name, main-module label, component version, type, deps, source)
        ("daemon", "colima-daemon (Go)", daemon_main, "1.0.0", "application",
         daemon_deps, "daemon/go.mod"),
        ("tui", "colima-tui (Go)", tui_main, "1.0.0", "application",
         tui_deps, "tui/go.mod"),
        ("linux", "colima-desktop-linux (Rust/GTK4)", linux_main, "0.2.0", "application",
         linux_deps, "linux/Cargo.lock"),
        ("windows", "ColimaDesktop.Windows (.NET/WinUI3)", "ColimaDesktop.Windows",
         "1.0.0", "application", win_deps,
         "windows/ColimaDesktop.Windows.csproj" + ("" if not win_transitive else " + dotnet list --include-transitive")),
        ("macos", "ColimaDesktop (Swift/SwiftUI)", "ColimaDesktop", "1.0.0",
         "application", swift_deps, "Package.resolved"),
    ]

    # --- emit per-component CycloneDX + collect aggregate ---
    aggregate_deps = []
    summary = []
    for key, disp, main_label, version, ctype, deps, source in components:
        bom = build_bom(disp, version, ctype, deps, timestamp=args.timestamp)
        write_json(os.path.join(cdx_dir, "%s.cdx.json" % key), bom)
        aggregate_deps.extend(deps)
        summary.append({
            "component": key,
            "display": disp,
            "main": main_label,
            "ecosystem": deps[0].ecosystem if deps else key,
            "source": source,
            "count": len(deps),
        })

    aggregate_deps = _dedupe_sort(aggregate_deps)
    agg = build_bom("colima-desktop (all components)", "1.0.0", "application",
                    aggregate_deps, timestamp=args.timestamp)
    write_json(os.path.join(cdx_dir, "colima-desktop.aggregate.cdx.json"), agg)

    # --- machine-readable summary for the report/ledger ---
    summary_obj = {
        "spec_version": CDX_SPEC_VERSION,
        "generator": "%s %s" % (GENERATOR_NAME, GENERATOR_VERSION),
        "total_unique_components": len(aggregate_deps),
        "components": summary,
    }
    write_json(os.path.join(out_dir, "components.json"), summary_obj)

    # --- human-readable inventory ---
    lines = []
    lines.append("# Software Bill of Materials — Component Inventory")
    lines.append("")
    lines.append("Machine-readable CycloneDX %s SBOMs live in `docs/sbom/cyclonedx/`." % CDX_SPEC_VERSION)
    lines.append("Regenerate with `make sbom` (see `scripts/sbom.sh`). Output is byte-stable.")
    lines.append("")
    lines.append("| Component | Ecosystem | Source manifest | Dependencies |")
    lines.append("|-----------|-----------|-----------------|-------------:|")
    eco_names = {"go": "Go modules", "rust": "Rust crates", "dotnet": "NuGet",
                 "swift": "Swift SPM"}
    for s in summary:
        eco = eco_names.get(s["ecosystem"], s["ecosystem"])
        lines.append("| %s | %s | `%s` | %d |" % (s["display"], eco, s["source"], s["count"]))
    lines.append("| **Aggregate (unique)** | all | — | **%d** |" % len(aggregate_deps))
    lines.append("")
    lines.append("## CycloneDX files")
    lines.append("")
    for key, disp, *_ in components:
        lines.append("- `docs/sbom/cyclonedx/%s.cdx.json` — %s" % (key, disp))
    lines.append("- `docs/sbom/cyclonedx/colima-desktop.aggregate.cdx.json` — merged, de-duplicated")
    lines.append("")
    with open(os.path.join(out_dir, "components.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    # --- stdout summary (consumed by scripts/sbom.sh) ---
    print("SBOM generated (CycloneDX %s) into %s" % (CDX_SPEC_VERSION, args.out_dir))
    for s in summary:
        print("  %-8s %-42s %4d components  (%s)" % (
            s["component"], s["display"], s["count"], s["source"]))
    print("  %-8s %-42s %4d components" % ("AGGREGATE", "unique across all ecosystems",
                                           len(aggregate_deps)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
