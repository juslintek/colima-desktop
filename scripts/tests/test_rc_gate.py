#!/usr/bin/env python3
"""
Tests for the release-candidate gate aggregator (scripts/rc-gate.sh, task 12.5).

The aggregator's job is COMPOSITION: invoke the task 12.1–12.4 sub-gates and turn their exit codes
into one release-candidate verdict. These tests exercise that composition WITHOUT running the heavy
real gates, by overriding each gate command via the documented `RC_*_CMD` env vars (default: the
real scripts). They assert:

  * the script is syntactically valid (`bash -n`);
  * `--list` prints the plan (every sub-gate + the CI-authoritative frontends.yml/test.yml) and exits 0;
  * `--selftest` proves the aggregation flips pass/fail;
  * the verdict is GREEN iff every gate that ran passed (a single failing gate => non-zero exit);
  * `--fast` defers verify.sh to CI and reads the committed security summary (honest partial);
  * a security summary carrying a CRITICAL finding fails the gate;
  * the per-gate `--skip-*` flags drop a gate from the verdict.

Runnable directly (`python3 scripts/tests/test_rc_gate.py`) or under pytest, mirroring the other
`scripts/tests/test_*.py` shape.
"""

import json
import os
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
RC_GATE = os.path.join(ROOT, "scripts", "rc-gate.sh")

# Stub every gate to a no-op success by default; individual tests flip one to failure. These are the
# documented override hooks the aggregator reads in place of the real 12.1–12.4 scripts.
STUB_PASS = {
    "RC_VERIFY_CMD": "true",
    "RC_SECURITY_CMD": "true",
    "RC_PERF_CMD": "true",
    "RC_A11Y_CMD": "true",
}


def _run(args, extra_env=None, logdir=None):
    env = dict(os.environ)
    env.update(STUB_PASS)
    env["RC_GATE_LOGDIR"] = logdir or tempfile.mkdtemp(prefix="rc-gate-test-")
    # Force the security gate away from the real committed summary unless a test opts in.
    env.setdefault("RC_SECURITY_SUMMARY", "/nonexistent")
    if extra_env:
        env.update(extra_env)
    proc = subprocess.run(
        ["bash", RC_GATE, *args],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=120,
    )
    return proc


def _write_summary(critical):
    fd, path = tempfile.mkstemp(prefix="vuln-summary-", suffix=".json")
    with os.fdopen(fd, "w") as fh:
        json.dump({"verdict": "GREEN" if critical == 0 else "RED",
                   "severity_totals": {"critical": critical}}, fh)
    return path


def test_syntax_valid():
    proc = subprocess.run(["bash", "-n", RC_GATE], capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr


def test_list_prints_plan():
    proc = _run(["--list"])
    assert proc.returncode == 0, proc.stderr
    out = proc.stdout
    for token in ("verify", "security", "perf", "a11y", "frontends.yml", "test.yml"):
        assert token in out, f"missing {token!r} in --list output:\n{out}"


def test_selftest_passes():
    # --selftest re-invokes the script with stub gates and asserts the verdict flips.
    proc = subprocess.run(["bash", RC_GATE, "--selftest"],
                          cwd=ROOT, env={**os.environ, "RC_GATE_LOGDIR": tempfile.mkdtemp()},
                          capture_output=True, text=True, timeout=120)
    assert proc.returncode == 0, f"selftest failed:\n{proc.stdout}\n{proc.stderr}"
    assert "selftest PASS" in proc.stdout


def test_all_gates_pass_is_green():
    # --full-security makes the security gate run RC_SECURITY_CMD (=true) rather than read a summary.
    proc = _run(["--full-security"])
    assert proc.returncode == 0, f"expected GREEN, got {proc.returncode}:\n{proc.stdout}"
    assert "RC-GATE GREEN" in proc.stdout


def test_single_failing_gate_blocks():
    proc = _run(["--full-security"], extra_env={"RC_A11Y_CMD": "false"})
    assert proc.returncode != 0, f"a failing a11y gate must block:\n{proc.stdout}"
    assert "NOT GREEN" in proc.stdout


def test_failing_verify_blocks():
    proc = _run(["--full-security"], extra_env={"RC_VERIFY_CMD": "false"})
    assert proc.returncode != 0, proc.stdout
    assert "NOT GREEN" in proc.stdout


def test_fast_defers_verify_and_is_partial_green():
    # In --fast the heavy verify.sh is deferred to CI and the security verdict comes from a summary.
    summary = _write_summary(critical=0)
    try:
        proc = _run(["--fast"], extra_env={"RC_SECURITY_SUMMARY": summary})
        assert proc.returncode == 0, f"expected partial GREEN:\n{proc.stdout}"
        assert "RC-GATE GREEN" in proc.stdout
        assert "CI-authoritative" in proc.stdout  # verify (+ frontends/tests) deferred honestly
    finally:
        os.unlink(summary)


def test_critical_vuln_summary_fails_security():
    summary = _write_summary(critical=1)
    try:
        proc = _run(["--fast"], extra_env={"RC_SECURITY_SUMMARY": summary})
        assert proc.returncode != 0, f"a CRITICAL finding must block:\n{proc.stdout}"
        assert "NOT GREEN" in proc.stdout
    finally:
        os.unlink(summary)


def test_skip_flags_drop_gate():
    proc = _run(["--full-security", "--skip-perf", "--skip-a11y"])
    assert proc.returncode == 0, proc.stdout
    assert "SKIP (user)" in proc.stdout


def _main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
            passed += 1
        except Exception as exc:  # noqa: BLE001 - test harness reports all failures
            print(f"FAIL {t.__name__}: {exc}")
    print(f"\n{passed}/{len(tests)} passed")
    return 0 if passed == len(tests) else 1


if __name__ == "__main__":
    raise SystemExit(_main())
