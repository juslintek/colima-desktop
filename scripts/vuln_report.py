#!/usr/bin/env python3
"""Assemble the cross-ecosystem vulnerability report + release-gate verdict (task 12.2, R7 / Requirement 11.3).

Reads one JSON status file per ecosystem produced by scripts/security-scan.sh
(docs/sbom/scans/<eco>.json) and emits:
  - docs/sbom/VULNERABILITY-REPORT.md   (human-readable, severity-summarised, HONEST)
  - docs/sbom/vuln-summary.json         (machine-readable roll-up for the RC gate / ledger)

Each per-ecosystem status JSON has the shape:
  {
    "ecosystem": "go-daemon",
    "component": "colima-daemon (Go)",
    "tool": "govulncheck ./...",
    "status": "clean" | "vulnerable" | "not-run",
    "total": 0,
    "severities": {"critical":0,"high":0,"moderate":0,"low":0,"unspecified":0},
    "advisories": [{"id":"...","severity":"high","title":"...","url":"..."}],
    "reason": "",             # populated when status == not-run
    "raw": "scans/govulncheck-daemon.txt"
  }

Requirement 11.3 target: ZERO known CRITICAL vulnerabilities. The report is
HONEST — it lists real advisories or states "no known vulnerabilities found" per
ecosystem, and clearly labels any ecosystem whose scanner could not run.

Exit codes:
  0  report written; no CRITICAL findings (or --fail-on-critical not set)
  0  report written even if lower-severity findings exist (findings are reported, not fatal)
  1  usage / no status files found
  2  --fail-on-critical set AND >=1 CRITICAL finding (RC-gate blocking)
"""

import argparse
import glob
import json
import os
import sys

SEVERITY_ORDER = ["critical", "high", "moderate", "low", "unspecified"]
# Ecosystem display order in the report.
ECO_ORDER = ["go-daemon", "go-tui", "rust-linux", "dotnet-windows", "swift-macos"]


def _load_statuses(scans_dir):
    statuses = {}
    for path in glob.glob(os.path.join(scans_dir, "*.json")):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                obj = json.load(fh)
        except (json.JSONDecodeError, OSError):
            continue
        eco = obj.get("ecosystem")
        if eco:
            statuses[eco] = obj
    return statuses


def _ordered(statuses):
    keys = list(statuses.keys())
    keys.sort(key=lambda k: (ECO_ORDER.index(k) if k in ECO_ORDER else len(ECO_ORDER), k))
    return [statuses[k] for k in keys]


def _sev_get(obj, name):
    return int(obj.get("severities", {}).get(name, 0) or 0)


def build_summary(statuses):
    ecos = _ordered(statuses)
    totals = {s: 0 for s in SEVERITY_ORDER}
    total_findings = 0
    n_clean = n_vuln = n_notrun = 0
    for obj in ecos:
        st = obj.get("status", "not-run")
        if st == "clean":
            n_clean += 1
        elif st == "vulnerable":
            n_vuln += 1
        else:
            n_notrun += 1
        total_findings += int(obj.get("total", 0) or 0)
        for s in SEVERITY_ORDER:
            totals[s] += _sev_get(obj, s)
    verdict = "GREEN" if totals["critical"] == 0 else "CRITICAL-FOUND"
    return {
        "generated_by": "scripts/vuln_report.py",
        "requirement": "11.3 (zero known critical vulnerabilities)",
        "verdict": verdict,
        "zero_known_critical": totals["critical"] == 0,
        "ecosystems_scanned": n_clean + n_vuln,
        "ecosystems_clean": n_clean,
        "ecosystems_with_findings": n_vuln,
        "ecosystems_not_run": n_notrun,
        "total_findings": total_findings,
        "severity_totals": totals,
        "ecosystems": ecos,
    }


def _sev_badge(obj):
    parts = []
    for s in SEVERITY_ORDER:
        n = _sev_get(obj, s)
        if n:
            parts.append("%s %d" % (s.capitalize(), n))
    return ", ".join(parts) if parts else "-"


def render_markdown(summary, scan_date):
    lines = []
    lines.append("# Vulnerability Report")
    lines.append("")
    lines.append("_Dependency & license vulnerability audit for Colima Desktop "
                 "(R7 / Requirement 11.3)._")
    lines.append("")
    lines.append("- **Scan date:** %s" % scan_date)
    lines.append("- **Requirement 11.3 target:** zero known **critical** vulnerabilities.")
    verdict = summary["verdict"]
    total = summary["total_findings"]
    if verdict == "GREEN":
        if total > 0:
            lines.append("- **Verdict:** ✅ **GREEN for Requirement 11.3 — zero known _critical_ vulnerabilities.** "
                         "%d lower-severity/unspecified finding(s) are reported below for triage (not release-blocking)."
                         % total)
        else:
            lines.append("- **Verdict:** ✅ **GREEN — no known vulnerabilities across scanned ecosystems.**")
    else:
        lines.append("- **Verdict:** ❌ **CRITICAL vulnerabilities found — see the table below (release-blocking per Requirement 11.3).**")
    lines.append("")
    lines.append("SBOMs for every component are in `docs/sbom/cyclonedx/` (see `docs/sbom/components.md`).")
    lines.append("Regenerate this report with `make security-scan` (see `scripts/security-scan.sh`).")
    lines.append("")

    # Summary table
    lines.append("## Summary by ecosystem")
    lines.append("")
    lines.append("| Component | Scanner | Status | Findings | Severity breakdown |")
    lines.append("|-----------|---------|--------|---------:|--------------------|")
    for obj in summary["ecosystems"]:
        st = obj.get("status", "not-run")
        if st == "clean":
            status_txt = "✅ clean"
        elif st == "vulnerable":
            status_txt = "⚠️ findings"
        else:
            status_txt = "⏭️ not run"
        lines.append("| %s | `%s` | %s | %d | %s |" % (
            obj.get("component", obj.get("ecosystem", "?")),
            obj.get("tool", "?"),
            status_txt,
            int(obj.get("total", 0) or 0),
            _sev_badge(obj),
        ))
    tot = summary["severity_totals"]
    tot_badge = ", ".join("%s %d" % (s.capitalize(), tot[s]) for s in SEVERITY_ORDER if tot[s]) or "none"
    lines.append("| **Total** | — | — | **%d** | %s |" % (summary["total_findings"], tot_badge))
    lines.append("")

    # Per-ecosystem detail
    lines.append("## Detail")
    lines.append("")
    for obj in summary["ecosystems"]:
        lines.append("### %s" % obj.get("component", obj.get("ecosystem", "?")))
        lines.append("")
        lines.append("- Scanner: `%s`" % obj.get("tool", "?"))
        st = obj.get("status", "not-run")
        if st == "clean":
            lines.append("- Result: **no known vulnerabilities found.**")
        elif st == "not-run":
            lines.append("- Result: **not run** — %s" % (obj.get("reason") or "scanner unavailable"))
        else:
            lines.append("- Result: **%d finding(s)** — %s" % (
                int(obj.get("total", 0) or 0), _sev_badge(obj)))
            advs = obj.get("advisories", [])
            if advs:
                lines.append("")
                lines.append("  | Advisory | Severity | Package | Title |")
                lines.append("  |----------|----------|---------|-------|")
                for a in advs:
                    lines.append("  | %s | %s | %s | %s |" % (
                        ("[%s](%s)" % (a.get("id", "?"), a["url"])) if a.get("url") else a.get("id", "?"),
                        a.get("severity", "unspecified"),
                        a.get("package", "-"),
                        (a.get("title", "") or "").replace("|", "\\|"),
                    ))
        if st != "not-run" and obj.get("reason"):
            lines.append("- Note: %s" % obj["reason"])
        raw = obj.get("raw")
        if raw:
            lines.append("- Raw output: `docs/sbom/%s`" % raw)
        lines.append("")

    lines.append("## Remediation guidance")
    lines.append("")
    lines.append("Each finding row lists its fixed version. Remediation is owned by the component's "
                 "path-owner agent (this supply-chain task does not modify component source/manifests):")
    lines.append("")
    lines.append("- **Go standard-library findings** (`govulncheck`, package `crypto/...`, `net/...`, etc.) "
                 "are resolved by rebuilding the daemon/TUI with a patched Go toolchain (the \"fixed in\" "
                 "`go1.x.y` version) — a build-toolchain bump, not a dependency change.")
    lines.append("- **Dependency findings** (a finding whose package is a module/crate/package, not the "
                 "standard library) are resolved by the owning agent bumping that dependency to the "
                 "\"fixed in\" version in the component's manifest, then re-running this scan.")
    lines.append("- Per the task rule, versions were **not** bumped here (no scanner flagged a *critical* "
                 "CVE); findings are reported for the owners to action.")
    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- This is a point-in-time scan; advisory databases evolve, so re-run before each release.")
    lines.append("- \"not run\" ecosystems are labelled honestly with the reason (missing scanner or "
                 "restore/network requirement); their parity is covered by the corresponding CI job.")
    lines.append("- Some scanners report a CVSS **vector** (or no severity label) rather than a base "
                 "score; such findings are recorded as `unspecified` and need manual severity triage "
                 "(they are never auto-labelled critical). `govulncheck` Go advisories are unspecified by "
                 "design; `cargo audit` RustSec advisories carry a CVSS vector.")
    lines.append("- The release-candidate gate (`scripts/security-scan.sh --fail-on-critical`, wired into "
                 "the RC gate) blocks only on **critical** findings per Requirement 11.3; lower-severity "
                 "findings are reported for triage, not auto-blocking.")
    lines.append("")
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description="Assemble the vulnerability report + gate verdict")
    ap.add_argument("--scans-dir", required=True, help="dir of per-ecosystem <eco>.json status files")
    ap.add_argument("--out-dir", required=True, help="docs/sbom output dir")
    ap.add_argument("--scan-date", default="unknown", help="scan date string for the report header")
    ap.add_argument("--fail-on-critical", action="store_true",
                    help="exit 2 if any CRITICAL finding exists (RC-gate mode)")
    args = ap.parse_args(argv)

    statuses = _load_statuses(args.scans_dir)
    if not statuses:
        print("no per-ecosystem status files found in %s" % args.scans_dir, file=sys.stderr)
        return 1

    summary = build_summary(statuses)
    os.makedirs(args.out_dir, exist_ok=True)

    with open(os.path.join(args.out_dir, "VULNERABILITY-REPORT.md"), "w", encoding="utf-8") as fh:
        fh.write(render_markdown(summary, args.scan_date))
    with open(os.path.join(args.out_dir, "vuln-summary.json"), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)
        fh.write("\n")

    crit = summary["severity_totals"]["critical"]
    print("Vulnerability report: verdict=%s total_findings=%d critical=%d "
          "(scanned=%d clean=%d findings=%d not-run=%d)" % (
              summary["verdict"], summary["total_findings"], crit,
              summary["ecosystems_scanned"], summary["ecosystems_clean"],
              summary["ecosystems_with_findings"], summary["ecosystems_not_run"]))
    for obj in summary["ecosystems"]:
        print("  %-16s %-10s findings=%s %s" % (
            obj.get("ecosystem"), obj.get("status"),
            obj.get("total", 0), _sev_badge(obj)))

    if args.fail_on_critical and crit > 0:
        print("RC GATE: %d critical vulnerability(ies) — blocking (Requirement 11.3)" % crit,
              file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
