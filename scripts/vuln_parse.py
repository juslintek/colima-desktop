#!/usr/bin/env python3
"""Parse a single ecosystem scanner's raw output into the per-ecosystem status JSON
consumed by scripts/vuln_report.py (task 12.2, R7 / Requirement 11.3).

Kinds:
  govulncheck  parse `govulncheck ./...` text  (Go)
  cargo-audit  parse `cargo audit --json` JSON  (Rust)
  dotnet       parse `dotnet list package --vulnerable` text (.NET)
  notrun       emit an honest not-run record with a reason

Prints the status JSON to stdout. Kept dependency-free + pure so its severity
classification and clean/vulnerable/not-run decision are unit-testable.
"""

import argparse
import json
import re
import sys

SEV_KEYS = ["critical", "high", "moderate", "low", "unspecified"]


def _empty_sev():
    return {k: 0 for k in SEV_KEYS}


def _norm_sev(s):
    s = (s or "").strip().lower()
    if s in ("critical",):
        return "critical"
    if s in ("high",):
        return "high"
    if s in ("moderate", "medium"):
        return "moderate"
    if s in ("low",):
        return "low"
    return "unspecified"


def parse_govulncheck(text, rc):
    """Go: parse code-reachable vulnerabilities from `govulncheck ./...` text.

    Each affecting vuln is a 'Vulnerability #N: <ID>' block followed by a
    description, 'More info:', a 'Module:'/'Standard library' line, and
    'Found in:'/'Fixed in:' package@version. govulncheck exits 3 when
    vulnerabilities are found, 0 when none, other on tool error. Severity is left
    'unspecified' — govulncheck's text emits no CVSS label, so we never fabricate one."""
    sev = _empty_sev()
    # Split into per-vulnerability blocks (the "Symbol Results" = code-reachable set).
    blocks = re.split(r"\nVulnerability #\d+:\s*", "\n" + text)
    advisories = []
    for block in blocks[1:]:
        lines = block.splitlines()
        if not lines:
            continue
        vid = lines[0].strip().rstrip(":")
        desc_parts, found, fixed, module = [], "", "", ""
        for ln in lines[1:]:
            s = ln.strip()
            if not s:
                if desc_parts:
                    break  # blank line after description ends it (before More info)
                continue
            if s.startswith("More info:"):
                break
            if s.startswith("Found in:") or s.startswith("Fixed in:") or \
               s.startswith("Module:") or s == "Standard library":
                break
            desc_parts.append(s)
        m_found = re.search(r"Found in:\s*(\S+)", block)
        m_fixed = re.search(r"Fixed in:\s*(\S+)", block)
        m_mod = re.search(r"\n\s*Module:\s*(\S+)", block)
        if m_found:
            found = m_found.group(1)
        if m_fixed:
            fixed = m_fixed.group(1)
        if m_mod:
            module = m_mod.group(1)
        elif "Standard library" in block:
            module = "Go standard library"
        title = " ".join(desc_parts).strip()
        if fixed:
            title = ("%s (fixed in %s)" % (title, fixed)).strip()
        pkg = found or module or "-"
        advisories.append({
            "id": vid,
            "severity": "unspecified",
            "package": pkg,
            "title": title,
            "url": "https://pkg.go.dev/vuln/%s" % vid,
        })
    # De-dup by id, preserve order.
    seen, uniq = set(), []
    for a in advisories:
        if a["id"] in seen:
            continue
        seen.add(a["id"])
        uniq.append(a)
    advisories = uniq

    clean_markers = ("No vulnerabilities found.", "No vulnerabilities found")
    if advisories:
        sev["unspecified"] = len(advisories)
        return _mk("vulnerable", len(advisories), sev, advisories)
    if rc == 0 or any(m in text for m in clean_markers):
        return _mk("clean", 0, sev, [])
    # rc != 0 and nothing parsed -> tool/network error
    reason = _last_meaningful_line(text) or ("govulncheck exited %s with no parseable result" % rc)
    return _mk("not-run", 0, sev, [], reason=reason)


def parse_cargo_audit(text):
    """Rust: parse `cargo audit --json`. total = vulnerabilities.count."""
    try:
        data = json.loads(text)
    except (json.JSONDecodeError, ValueError):
        reason = _last_meaningful_line(text) or "cargo audit produced no JSON (advisory DB fetch or tool error)"
        return _mk("not-run", 0, _empty_sev(), [], reason=reason)
    vulns = data.get("vulnerabilities", {}) or {}
    count = int(vulns.get("count", 0) or 0)
    sev = _empty_sev()
    advisories = []
    for item in vulns.get("list", []) or []:
        adv = item.get("advisory", {}) or {}
        pkg = item.get("package", {}) or {}
        # RustSec `cvss` is a vector string, not a label; derive severity from the
        # base score when we can, else 'unspecified' (never fabricate 'critical').
        severity = _severity_from_cvss(adv.get("cvss"))
        sev[severity] += 1
        advisories.append({
            "id": adv.get("id", "?"),
            "severity": severity,
            "package": "%s %s" % (pkg.get("name", "?"), pkg.get("version", "")),
            "title": adv.get("title", ""),
            "url": adv.get("url") or ("https://rustsec.org/advisories/%s" % adv.get("id", "")),
        })
    # Recompute count from the list if the header count is missing.
    if not count:
        count = len(advisories)
    # Informational warnings (unmaintained/unsound/notice) are NOT vulnerabilities;
    # surface them as a note without inflating the finding count.
    warn_items = []
    for kind, lst in (data.get("warnings", {}) or {}).items():
        for w in (lst or []):
            adv = w.get("advisory", {}) or {}
            pkg = (w.get("package", {}) or {}).get("name", "?")
            warn_items.append("%s (%s, %s)" % (adv.get("id", "?"), pkg, kind))
    reason = ""
    if warn_items:
        reason = "%d informational advisory warning(s), not vulnerabilities: %s" % (
            len(warn_items), "; ".join(warn_items))
    status = "vulnerable" if count > 0 else "clean"
    return _mk(status, count, sev, advisories, reason=reason)


def _severity_from_cvss(cvss):
    """Map a CVSS *base score* to a label, ONLY when the field is a plain numeric
    score (e.g. "9.8"). RustSec's `cvss` is normally a vector string
    (e.g. "CVSS:3.1/AV:N/AC:L/...") that carries NO base score — parsing a number
    out of it would grab the "3.1" version and mis-classify, so a vector (or None)
    returns 'unspecified'. We never fabricate a severity from an unscored vector."""
    if not cvss or not isinstance(cvss, str):
        return "unspecified"
    s = cvss.strip()
    m = re.fullmatch(r"(\d+(?:\.\d+)?)", s)
    if not m:
        # CVSS vector without an explicit base score -> unspecified (honest).
        return "unspecified"
    try:
        score = float(m.group(1))
    except ValueError:
        return "unspecified"
    if score >= 9.0:
        return "critical"
    if score >= 7.0:
        return "high"
    if score >= 4.0:
        return "moderate"
    if score > 0.0:
        return "low"
    return "unspecified"


_DOTNET_ROW = re.compile(
    r"^\s*>\s+(\S+)\s+.*?\b(Critical|High|Moderate|Medium|Low)\b\s+(https?://\S+)",
    re.IGNORECASE)


def parse_dotnet(text, rc):
    """.NET: parse `dotnet list package --vulnerable --include-transitive` text."""
    sev = _empty_sev()
    advisories = []
    for line in text.splitlines():
        m = _DOTNET_ROW.match(line)
        if not m:
            continue
        pkg, severity_raw, url = m.group(1), m.group(2), m.group(3)
        severity = _norm_sev(severity_raw)
        sev[severity] += 1
        gid = url.rstrip("/").split("/")[-1]
        advisories.append({
            "id": gid or "advisory",
            "severity": severity,
            "package": pkg,
            "title": "",
            "url": url,
        })
    if advisories:
        return _mk("vulnerable", len(advisories), sev, advisories)
    if re.search(r"has no vulnerable packages", text) or rc == 0:
        return _mk("clean", 0, sev, [])
    reason = _last_meaningful_line(text) or ("dotnet list exited %s (restore/network required)" % rc)
    return _mk("not-run", 0, sev, [], reason=reason)


def _last_meaningful_line(text):
    for line in reversed((text or "").splitlines()):
        s = line.strip()
        if s:
            return s[:300]
    return ""


def _mk(status, total, sev, advisories, reason=""):
    return {
        "status": status,
        "total": total,
        "severities": sev,
        "advisories": advisories,
        "reason": reason,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description="Parse one ecosystem scanner output into status JSON")
    ap.add_argument("--kind", required=True,
                    choices=["govulncheck", "cargo-audit", "dotnet", "notrun"])
    ap.add_argument("--ecosystem", required=True)
    ap.add_argument("--component", required=True)
    ap.add_argument("--tool", required=True)
    ap.add_argument("--raw", default=None, help="raw scanner output file")
    ap.add_argument("--raw-rel", default=None, help="repo-relative path to the raw file for the report")
    ap.add_argument("--rc", type=int, default=0)
    ap.add_argument("--reason", default="")
    args = ap.parse_args(argv)

    text = ""
    if args.raw:
        try:
            with open(args.raw, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            text = ""

    if args.kind == "govulncheck":
        result = parse_govulncheck(text, args.rc)
    elif args.kind == "cargo-audit":
        result = parse_cargo_audit(text)
    elif args.kind == "dotnet":
        result = parse_dotnet(text, args.rc)
    else:  # notrun
        result = _mk("not-run", 0, _empty_sev(), [], reason=args.reason or "scanner not available")

    result["ecosystem"] = args.ecosystem
    result["component"] = args.component
    result["tool"] = args.tool
    if args.raw_rel:
        result["raw"] = args.raw_rel
    # stable key order
    ordered = {k: result[k] for k in
               ["ecosystem", "component", "tool", "status", "total",
                "severities", "advisories", "reason"] if k in result}
    if "raw" in result:
        ordered["raw"] = result["raw"]
    print(json.dumps(ordered, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
