#!/usr/bin/env python3
"""Tests for the supply-chain scan pipeline (task 12.2, R7 / Requirement 11.3).

Covers scripts/vuln_parse.py (per-scanner output -> status JSON) and
scripts/vuln_report.py (status JSON -> report + critical gate verdict):
  - parser clean / vulnerable / not-run classification for govulncheck, cargo audit, dotnet
  - CVSS-score -> severity mapping
  - report verdict is GREEN iff zero CRITICAL, and --fail-on-critical exits 2 iff
    a CRITICAL finding exists (>=100 randomized iterations)

Self-contained: runnable directly (`python3 scripts/tests/test_vuln_report.py`)
and via pytest. Imports the sibling scripts by file path.
"""

import importlib.util
import json
import os
import random
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_SCRIPTS = os.path.dirname(_HERE)


def _load(mod_name, filename):
    spec = importlib.util.spec_from_file_location(mod_name, os.path.join(_SCRIPTS, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

VP = _load("vuln_parse", "vuln_parse.py")
VR = _load("vuln_report", "vuln_report.py")

FAILURES = []


def check(cond, msg):
    if not cond:
        FAILURES.append(msg)
        print("FAIL:", msg)


# --------------------------------------------------------------------------- parsers

GV_CLEAN = "=== Symbol Results ===\n\nNo vulnerabilities found.\n"
GV_VULN = """=== Symbol Results ===

Vulnerability #1: GO-2026-4762
    Authorization bypass in gRPC-Go via missing leading slash in :path
  More info: https://pkg.go.dev/vuln/GO-2026-4762
  Module: google.golang.org/grpc
    Found in: google.golang.org/grpc@v1.64.0
    Fixed in: google.golang.org/grpc@v1.79.3
    Example traces found:
      #1: cmd/main.go:231:27: cmd.serve calls grpc.Server.Serve

Vulnerability #2: GO-2026-4971
    Panic in Dial and LookupPort when handling NUL byte on Windows in net
  More info: https://pkg.go.dev/vuln/GO-2026-4971
  Standard library
    Found in: net@go1.26.2
    Fixed in: net@go1.26.3
"""


def test_govulncheck():
    clean = VP.parse_govulncheck(GV_CLEAN, 0)
    check(clean["status"] == "clean" and clean["total"] == 0, "govulncheck clean")

    vuln = VP.parse_govulncheck(GV_VULN, 3)
    check(vuln["status"] == "vulnerable" and vuln["total"] == 2, "govulncheck vulnerable count=2")
    ids = [a["id"] for a in vuln["advisories"]]
    check(ids == ["GO-2026-4762", "GO-2026-4971"], "govulncheck ids parsed in order")
    grpc = vuln["advisories"][0]
    check(grpc["package"] == "google.golang.org/grpc@v1.64.0", "govulncheck package captured")
    check("fixed in google.golang.org/grpc@v1.79.3" in grpc["title"], "govulncheck fix version in title")
    check(vuln["severities"]["unspecified"] == 2 and vuln["severities"]["critical"] == 0,
          "govulncheck severity unspecified (never fabricates critical)")

    # rc!=0 with unparseable text -> not-run
    nr = VP.parse_govulncheck("some transient tool error\n", 1)
    check(nr["status"] == "not-run", "govulncheck error -> not-run")


def test_cargo_audit():
    clean = VP.parse_cargo_audit(json.dumps({
        "vulnerabilities": {"found": False, "count": 0, "list": []},
        "warnings": {"unmaintained": [
            {"kind": "unmaintained", "package": {"name": "rustls-pemfile"},
             "advisory": {"id": "RUSTSEC-2025-0134"}}]},
    }))
    check(clean["status"] == "clean" and clean["total"] == 0, "cargo audit clean")
    check("RUSTSEC-2025-0134" in clean["reason"] and "not vulnerabilities" in clean["reason"],
          "cargo audit surfaces informational warning as a note, not a finding")

    # A plain numeric CVSS score maps to a label (exercises the mapping path).
    vuln = VP.parse_cargo_audit(json.dumps({
        "vulnerabilities": {"found": True, "count": 1, "list": [
            {"advisory": {"id": "RUSTSEC-2024-0001", "title": "x", "url": "u", "cvss": "9.8"},
             "package": {"name": "foo", "version": "1.0"}}]},
        "warnings": {},
    }))
    check(vuln["status"] == "vulnerable" and vuln["total"] == 1, "cargo audit vulnerable")
    check(vuln["severities"]["critical"] == 1, "cargo audit plain cvss 9.8 -> critical")

    # A real RustSec CVSS *vector* (no base score) -> unspecified, still counted.
    vec = VP.parse_cargo_audit(json.dumps({
        "vulnerabilities": {"found": True, "count": 1, "list": [
            {"advisory": {"id": "RUSTSEC-2024-0002", "cvss":
                          "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"},
             "package": {"name": "bar", "version": "2.0"}}]},
        "warnings": {},
    }))
    check(vec["total"] == 1 and vec["severities"]["unspecified"] == 1
          and vec["severities"]["critical"] == 0,
          "cargo audit CVSS vector (no score) -> unspecified, not fabricated critical")

    nr = VP.parse_cargo_audit("not json (advisory db fetch failed)")
    check(nr["status"] == "not-run", "cargo audit non-json -> not-run")


def test_dotnet():
    clean = VP.parse_dotnet("The given project `X` has no vulnerable packages given the current sources.\n", 0)
    check(clean["status"] == "clean", "dotnet clean")

    vuln_txt = (
        "Project `X` has the following vulnerable packages\n"
        "   [net8.0]:\n"
        "   > System.Text.Json   8.0.0   8.0.0   High   https://github.com/advisories/GHSA-hh2w-p6rv-4g7w\n"
        "   > SomePkg             1.2.3   1.2.3   Critical   https://github.com/advisories/GHSA-xxxx-yyyy-zzzz\n"
    )
    vuln = VP.parse_dotnet(vuln_txt, 1)
    check(vuln["status"] == "vulnerable" and vuln["total"] == 2, "dotnet vulnerable count=2")
    check(vuln["severities"]["critical"] == 1 and vuln["severities"]["high"] == 1,
          "dotnet severity high+critical parsed")


def test_severity_from_cvss():
    check(VP._severity_from_cvss("9.1") == "critical", "plain cvss 9.1 critical")
    check(VP._severity_from_cvss("7.5") == "high", "plain cvss 7.5 high")
    check(VP._severity_from_cvss("5.0") == "moderate", "plain cvss 5.0 moderate")
    check(VP._severity_from_cvss("2.1") == "low", "plain cvss 2.1 low")
    check(VP._severity_from_cvss(None) == "unspecified", "cvss none unspecified")
    # A CVSS vector carries no base score -> unspecified (must NOT grab the "3.1" version).
    check(VP._severity_from_cvss("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H") == "unspecified",
          "cvss vector -> unspecified (not mis-read as low from version)")


# --------------------------------------------------------------------------- report + gate

def _status(eco, status, sev):
    return {"ecosystem": eco, "component": eco, "tool": "t", "status": status,
            "total": sum(sev.values()), "severities": {**{k: 0 for k in VP.SEV_KEYS}, **sev},
            "advisories": [], "reason": ""}


def test_report_verdict_and_gate():
    # No critical -> GREEN; --fail-on-critical exits 0.
    with tempfile.TemporaryDirectory() as d:
        scans = os.path.join(d, "scans")
        os.makedirs(scans)
        for i, st in enumerate([
            _status("go-daemon", "vulnerable", {"unspecified": 6}),
            _status("rust-linux", "clean", {}),
            _status("dotnet-windows", "clean", {}),
        ]):
            with open(os.path.join(scans, "e%d.json" % i), "w") as fh:
                json.dump(st, fh)
        rc = VR.main(["--scans-dir", scans, "--out-dir", d, "--fail-on-critical"])
        check(rc == 0, "no critical -> gate exit 0")
        summary = json.load(open(os.path.join(d, "vuln-summary.json")))
        check(summary["verdict"] == "GREEN" and summary["zero_known_critical"] is True,
              "no critical -> verdict GREEN")
        check(os.path.isfile(os.path.join(d, "VULNERABILITY-REPORT.md")), "report written")

    # A critical -> CRITICAL-FOUND; --fail-on-critical exits 2.
    with tempfile.TemporaryDirectory() as d:
        scans = os.path.join(d, "scans")
        os.makedirs(scans)
        with open(os.path.join(scans, "a.json"), "w") as fh:
            json.dump(_status("dotnet-windows", "vulnerable", {"critical": 1, "high": 2}), fh)
        rc = VR.main(["--scans-dir", scans, "--out-dir", d, "--fail-on-critical"])
        check(rc == 2, "critical present -> gate exit 2")
        rc0 = VR.main(["--scans-dir", scans, "--out-dir", d])  # no gate flag
        check(rc0 == 0, "critical present but no gate flag -> exit 0 (findings reported, not fatal)")


def test_gate_property(iterations=150):
    """>=100 randomized ecosystems: verdict GREEN iff zero critical; gate exits 2 iff critical>0."""
    rng = random.Random(12321)
    ran = 0
    for _ in range(iterations):
        with tempfile.TemporaryDirectory() as d:
            scans = os.path.join(d, "scans")
            os.makedirs(scans)
            total_crit = 0
            for i in range(rng.randint(1, 5)):
                sev = {}
                for k in VP.SEV_KEYS:
                    n = rng.randint(0, 3)
                    if n:
                        sev[k] = n
                total_crit += sev.get("critical", 0)
                st = "clean" if not sev else "vulnerable"
                with open(os.path.join(scans, "e%d.json" % i), "w") as fh:
                    json.dump(_status("eco%d" % i, st, sev), fh)
            rc_gate = VR.main(["--scans-dir", scans, "--out-dir", d, "--fail-on-critical"])
            summary = json.load(open(os.path.join(d, "vuln-summary.json")))
            expect_green = (total_crit == 0)
            check((summary["verdict"] == "GREEN") == expect_green,
                  "verdict GREEN iff zero critical (crit=%d)" % total_crit)
            check((rc_gate == 2) == (total_crit > 0),
                  "gate exit 2 iff critical>0 (crit=%d rc=%d)" % (total_crit, rc_gate))
            ran += 1
    check(ran >= 100, "ran >= 100 iterations (%d)" % ran)


def main():
    test_govulncheck()
    test_cargo_audit()
    test_dotnet()
    test_severity_from_cvss()
    test_report_verdict_and_gate()
    test_gate_property()
    if FAILURES:
        print("\nRESULT: %d FAILURE(S)" % len(FAILURES))
        return 1
    print("RESULT: ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
