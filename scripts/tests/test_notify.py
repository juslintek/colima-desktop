#!/usr/bin/env python3
"""Property tests for the completion-notification service — scripts/notify/{render,deliver,scrub}.py (task 14.4).

Feature: cross-platform-live-verification

These tests treat the task-14.1/14.2/14.3 notify modules as the units under test. The three
hyphen-free modules are loaded in-process via importlib.util.spec_from_file_location (registered in
sys.modules so deliver.py's internal `import render` / `import scrub` resolve to the SAME objects),
so the pure functions are exercised directly — fast, no subprocess, immune to the interactive
repo-scan startup hook + ~30s output cap that make the shell flaky here.

Three design correctness properties are asserted over >=100 randomized, seeded (reproducible)
iterations each, with SMART generators that constrain to the realistic input space (clean version
tags / roadmap ids, non-secret verify lines) so a counterexample is a genuine defect rather than an
artifact of the modules' intentional strip/scrub behavior:

  * Property 23 — Notification rendering completeness (Requirements 13.1, 13.2)
      For ANY generated NotificationSummary, render(summary) yields an email addressed to
      EMAIL_RECIPIENT whose body contains the version, the verify result, and EVERY roadmap id, and
      an SMS addressed to SMS_RECIPIENT whose text contains the version and the verify result. Also
      asserts RenderError is raised for a missing version / empty verify_result / empty roadmap list.

  * Property 24 — Notification credentials-absent fallback (Requirement 13.4)
      For ANY randomized subset of present/absent email+SMS credential env vars, deliver_all(rendered,
      env=<subset>, out_dir=<temp>) NEVER raises and NEVER fails the release: each required channel
      whose creds are absent/partial returns status `drafted` with an existing draft file under the
      ISOLATED temp out_dir; the draft content carries the rendered message (version + verify result;
      the email carries every roadmap id + the fixed recipient); and a send-script + combined JSON are
      emitted. Env is injected as a dict (the real environment is never read), a fresh temp dir is
      used per iteration (never the repo dist/notifications), and complete-cred iterations pass
      force_draft=True so the test performs NO real network I/O.

  * Property 25 — Secret hygiene invariant (Requirements 8.6, 13.6)
      For ANY text built from a random mix of non-secret content + SYNTHETIC secret patterns (fake
      SMTP passwords, fake Twilio SID/token, fake bearer/JWT, fake KEY=VALUE secrets, PEM blocks) +
      declared known_secrets, scrub(text, known_secrets) output contains NONE of the injected secrets,
      assert_clean(scrub(...)) never raises (completeness), scrub is idempotent
      (scrub(scrub(x)) == scrub(x)), and the non-secret content survives. SYNTHETIC/example secrets
      ONLY — never a real credential.

Runnable directly (writes a summary log + JSON to /tmp and exits nonzero on any failure):

    python3 scripts/tests/test_notify.py                  # 150 iters/property
    python3 scripts/tests/test_notify.py --iters 250 --seed 42

and also under pytest (the test_* functions assert zero property failures, >=100 iters).

It NEVER modifies render.py / deliver.py / scrub.py. A property that does not hold is surfaced as a
counterexample (a candidate real bug), never silently patched. No real secret is ever embedded, no
real network send is performed, no real environment is read, and nothing is written to the repo
`dist/` — every iteration uses tempfile dirs + injected env dicts + a seeded RNG.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import random
import sys
import tempfile
import time
import traceback
from pathlib import Path

# --------------------------------------------------------------------------- #
# Locations & module import (hyphen-free filenames -> importlib by path)
# --------------------------------------------------------------------------- #
REPO_ROOT = Path(__file__).resolve().parents[2]
NOTIFY_DIR = REPO_ROOT / "scripts" / "notify"

LOG_PATH = Path(os.environ.get("NOTIFY_PBT_LOG", "/tmp/notify_pbt.log"))
SUMMARY_PATH = Path(os.environ.get("NOTIFY_PBT_SUMMARY", "/tmp/notify_pbt_summary.json"))

_LOG_FH = None


def log(msg: str) -> None:
    """Print to stdout and (if open) to the /tmp log, flushed, so a backgrounded run can be
    observed by reading the file back."""
    line = str(msg)
    print(line, flush=True)
    global _LOG_FH
    if _LOG_FH is not None:
        _LOG_FH.write(line + "\n")
        _LOG_FH.flush()


def _load_module(name: str):
    """Load scripts/notify/<name>.py as a module and register it in sys.modules so cross-imports
    (deliver.py does `import render` / `import scrub`) resolve to the same object."""
    spec = importlib.util.spec_from_file_location(name, str(NOTIFY_DIR / (name + ".py")))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


# Put the notify dir on sys.path (deliver.py also does this) so its sibling imports resolve, then
# load render + scrub BEFORE deliver so deliver's `import render`/`import scrub` find them.
if str(NOTIFY_DIR) not in sys.path:
    sys.path.insert(0, str(NOTIFY_DIR))
render = _load_module("render")
scrub = _load_module("scrub")
deliver = _load_module("deliver")

# Constants pulled from the modules so the tests stay in lockstep with them.
EMAIL_RECIPIENT = render.EMAIL_RECIPIENT
SMS_RECIPIENT = render.SMS_RECIPIENT
RenderError = render.RenderError
SecretLeakError = scrub.SecretLeakError
EMAIL = deliver.EMAIL
SMS = deliver.SMS
STATUS_SENT = deliver.STATUS_SENT
STATUS_DRAFTED = deliver.STATUS_DRAFTED
STATUS_SKIPPED = deliver.STATUS_SKIPPED

# Character alphabets for SYNTHETIC secret/value generation (never a real credential).
_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
_HEX = "0123456789abcdef"
_MIXED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
_UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ"


# --------------------------------------------------------------------------- #
# Small helpers
# --------------------------------------------------------------------------- #
def _rand_str(rng, n, alphabet):
    return "".join(rng.choice(alphabet) for _ in range(n))


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _rmtree_quiet(path):
    import shutil
    try:
        shutil.rmtree(path)
    except OSError:
        pass


def _short_tb():
    return traceback.format_exc().strip().splitlines()[-1]


def _raises_render_error(fn) -> bool:
    """Return True iff fn() raises RenderError (a wrong/absent exception is a failure)."""
    try:
        fn()
        return False
    except RenderError:
        return True
    except Exception:
        return False


def _with(summary, **changes):
    """Return a copy of a NotificationSummary with field overrides (frozen dataclass -> rebuild)."""
    return render.NotificationSummary(
        version=changes.get("version", summary.version),
        roadmap_ids=changes.get("roadmap_ids", list(summary.roadmap_ids)),
        verify_result=changes.get("verify_result", summary.verify_result),
        notes_url=changes.get("notes_url", summary.notes_url),
        headline=changes.get("headline", summary.headline),
        highlights=changes.get("highlights", list(summary.highlights)),
    )


# --------------------------------------------------------------------------- #
# Result accumulator
# --------------------------------------------------------------------------- #
class PropResult:
    def __init__(self, name):
        self.name = name
        self.ran = 0
        self.passed = 0
        self.failures = []  # list of counterexample dicts

    @property
    def failed(self):
        return len(self.failures)

    def record_pass(self):
        self.ran += 1
        self.passed += 1

    def record_fail(self, detail):
        self.ran += 1
        self.failures.append(detail)
        if len(self.failures) <= 5:
            log("  [COUNTEREXAMPLE] %s" % json.dumps(detail)[:700])


# --------------------------------------------------------------------------- #
# Shared summary generator (used by Property 23 + 24)
# --------------------------------------------------------------------------- #
def gen_version(rng):
    """A realistic, whitespace-free version tag (render strips, so surrounding ws would be a
    non-bug false counterexample -- we generate the true input space instead)."""
    v = "v%d.%d.%d" % (rng.randint(0, 9), rng.randint(0, 20), rng.randint(0, 50))
    if rng.random() < 0.30:
        v += "-rc%d" % rng.randint(1, 5)
    return v


def gen_roadmap_ids(rng):
    """1..9 clean, non-empty, comma-free roadmap ids (duplicates allowed -- each must still appear)."""
    n = rng.randint(1, 9)
    out = []
    for _ in range(n):
        c = rng.random()
        if c < 0.60:
            out.append("R%d" % rng.randint(0, 30))
        elif c < 0.85:
            out.append("WAVE%d" % rng.randint(0, 12))
        else:
            out.append(_rand_str(rng, rng.randint(2, 4), _UPPER) + str(rng.randint(0, 99)))
    return out


def gen_verify_result(rng):
    """A non-secret one-line verification result (no high-entropy token / secret-like assignment),
    so it survives the delivery scrub verbatim and the content-presence assertions are exact."""
    status = rng.choice(["GREEN", "PASS", "OK", "ALL GREEN"])
    passed = rng.randint(1, 999)
    failed = rng.randint(0, 9)
    withheld = rng.randint(0, 99)
    tail = rng.choice([
        "CI green across macOS/Windows/Linux",
        "all gates pass",
        "frontends 9/9",
        "live desktop-e2e verified",
    ])
    return "RESULT: %s -- %d checks passed, %d failed, %d withheld; %s" % (
        status, passed, failed, withheld, tail)


def gen_phrase(rng):
    words = ["release", "engineered", "across", "all", "platforms", "verified", "live",
             "backend", "green", "checks", "passed", "signed", "artifacts", "cleanly"]
    return " ".join(rng.choice(words) for _ in range(rng.randint(4, 9)))


def gen_summary(rng):
    version = gen_version(rng)
    ids = gen_roadmap_ids(rng)
    verify = gen_verify_result(rng)
    notes = "" if rng.random() < 0.5 else "https://example.test/tag/%s" % version
    highlights = [] if rng.random() < 0.5 else [gen_phrase(rng) for _ in range(rng.randint(1, 3))]
    headline = "" if rng.random() < 0.5 else gen_phrase(rng)
    return render.NotificationSummary(version=version, roadmap_ids=ids, verify_result=verify,
                                      notes_url=notes, headline=headline, highlights=highlights)


# --------------------------------------------------------------------------- #
# Property 23 — Notification rendering completeness (Requirements 13.1, 13.2)
# --------------------------------------------------------------------------- #
def run_property_23(seed_rng, iters):
    r = PropResult("Property 23 (notification rendering completeness)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            summary = gen_summary(rng)
            rendered = render.render(summary)
            email = rendered.email
            sms = rendered.sms

            # Email: fixed recipient + version + every roadmap id + verify result (R13.1)
            assert email.to == EMAIL_RECIPIENT, "email addressed to EMAIL_RECIPIENT"
            assert summary.version in email.subject, "version in email subject"
            assert summary.version in email.body, "version in email body"
            assert summary.verify_result in email.body, "verify_result in email body"
            for rid in summary.roadmap_ids:
                assert rid in email.body, "roadmap id %r in email body" % rid

            # SMS: fixed recipient + version + verify result (R13.2)
            assert sms.to == SMS_RECIPIENT, "sms addressed to SMS_RECIPIENT"
            assert summary.version in sms.text, "version in sms text"
            assert summary.verify_result in sms.text, "verify_result in sms text"

            # render_email / render_sms are consistent with render()
            assert render.render_email(summary).body == email.body, "render_email consistent"
            assert render.render_sms(summary).text == sms.text, "render_sms consistent"

            # RenderError on a missing version / empty verify_result / empty roadmap list
            assert _raises_render_error(lambda: render.render(_with(summary, version=""))), \
                "empty version must raise RenderError"
            assert _raises_render_error(lambda: render.render(_with(summary, version="   "))), \
                "whitespace version must raise RenderError"
            assert _raises_render_error(lambda: render.render(_with(summary, verify_result=""))), \
                "empty verify_result must raise RenderError"
            assert _raises_render_error(lambda: render.render(_with(summary, roadmap_ids=[]))), \
                "empty roadmap list must raise RenderError"
            assert _raises_render_error(lambda: render.render(_with(summary, roadmap_ids=["", "  "]))), \
                "all-blank roadmap list must raise RenderError"

            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Property 24 — Notification credentials-absent fallback (Requirement 13.4)
# --------------------------------------------------------------------------- #
_ALL_VARS_P24 = ("SMTP_HOST", "SMTP_USER", "SMTP_PASS", "SENDGRID_API_KEY",
                 "TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_FROM")


def _synthetic_env_value(rng, var):
    """SYNTHETIC-ONLY credential env value (never a real credential)."""
    if var == "SMTP_HOST":
        return "smtp.example.test"
    if var == "SMTP_USER":
        return "notifier@example.test"
    if var == "TWILIO_FROM":
        return "+1555%07d" % rng.randint(0, 9999999)
    if var == "SENDGRID_API_KEY":
        return "SG." + _rand_str(rng, 22, _B64) + "." + _rand_str(rng, 40, _B64)
    if var == "TWILIO_ACCOUNT_SID":
        return "AC" + _rand_str(rng, 32, _HEX)
    if var == "TWILIO_AUTH_TOKEN":
        return _rand_str(rng, 32, _HEX)
    if var == "SMTP_PASS":
        return "Pw-" + _rand_str(rng, 24, _MIXED)
    return _rand_str(rng, 20, _MIXED)


def gen_env_subset(rng):
    """A random present/absent subset of the email+SMS credential env vars (injected dict; the real
    environment is never read)."""
    env = {}
    for var in _ALL_VARS_P24:
        if rng.random() < 0.5:
            env[var] = _synthetic_env_value(rng, var)
    return env


def run_property_24(seed_rng, iters):
    r = PropResult("Property 24 (credentials-absent fallback)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        tmp = tempfile.mkdtemp(prefix="notify-p24-")
        try:
            summary = gen_summary(rng)
            rendered = render.render(summary)
            env = gen_env_subset(rng)

            email_complete = deliver.load_email_creds(env).complete
            sms_complete = deliver.load_sms_creds(env).complete
            # Keep the test hermetic/offline: if any required channel is complete, force the draft
            # path so deliver() never attempts a real send (no network I/O).
            force = email_complete or sms_complete

            results = deliver.deliver_all(rendered, env=env, version=summary.version,
                                          out_dir=tmp, force_draft=force)

            # deliver_all NEVER raises for absent creds and returns a normal result set (release not
            # failed). Every status is a known non-failure/known enum value.
            assert isinstance(results, list) and len(results) >= 2, "results is a non-trivial list"
            for res in results:
                assert res.status in (STATUS_SENT, STATUS_DRAFTED, STATUS_SKIPPED), \
                    "status in {sent,drafted,skipped}"
                assert res.status != STATUS_SENT, "offline test: no channel is ever really sent"

            by = {res.channel: res for res in results}
            assert EMAIL in by and SMS in by, "both required channels attempted"

            secrets = deliver.known_secret_values(env)
            for ch, complete in ((EMAIL, email_complete), (SMS, sms_complete)):
                res = by[ch]
                if not complete:
                    # Credentials absent/partial -> MUST draft (the Property 24 core claim).
                    assert res.status == STATUS_DRAFTED, "%s must draft when creds absent/partial" % ch
                # Whether forced (complete) or naturally (incomplete), the channel drafts here.
                assert res.status == STATUS_DRAFTED, "%s drafted in the offline test" % ch
                assert res.draft_path and os.path.exists(res.draft_path), "%s draft file exists" % ch

                # The draft lives under the ISOLATED temp out_dir, never the repo dist/notifications.
                draft_dir = os.path.dirname(os.path.abspath(res.draft_path))
                assert draft_dir == os.path.abspath(tmp), "%s draft under the temp out_dir" % ch
                assert os.path.abspath(deliver.DEFAULT_OUT_DIR) not in os.path.abspath(res.draft_path), \
                    "never writes to the repo dist/notifications"

                text = _read(res.draft_path)
                assert summary.version in text, "%s draft carries the version" % ch
                assert summary.verify_result in text, "%s draft carries the verify result" % ch
                if ch == EMAIL:
                    for rid in summary.roadmap_ids:
                        assert rid in text, "email draft carries roadmap id %r" % rid
                    assert EMAIL_RECIPIENT in text, "email draft carries the fixed recipient"
                else:
                    assert SMS_RECIPIENT in text, "sms draft carries the fixed recipient"
                for s in secrets:
                    assert s not in text, "no secret substring leaked into the %s draft" % ch

            # A draft was written -> the re-runnable send script + combined JSON are emitted, and are
            # themselves secret-clean.
            if any(res.status == STATUS_DRAFTED for res in results):
                script = os.path.join(tmp, deliver.SEND_SCRIPT_NAME)
                combined = os.path.join(tmp, deliver.combined_filename(summary.version))
                assert os.path.exists(script), "send-notifications.sh emitted"
                assert os.path.exists(combined), "combined notifications JSON emitted"
                for f in (script, combined):
                    body = _read(f)
                    for s in secrets:
                        assert s not in body, "no secret substring leaked into %s" % os.path.basename(f)

            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
        finally:
            _rmtree_quiet(tmp)
    return r


# --------------------------------------------------------------------------- #
# Property 25 — Secret hygiene invariant (Requirements 8.6, 13.6)
# --------------------------------------------------------------------------- #
# Each maker returns (segment_text, secret_substring_that_must_be_gone, is_known_secret).
# SYNTHETIC/example patterns ONLY -- never a real credential.
def _mk_smtp_pass(rng):
    val = "Pw-" + _rand_str(rng, 24, _MIXED)
    return "SMTP_PASS=%s" % val, val, False


def _mk_sendgrid(rng):
    tok = "SG." + _rand_str(rng, 22, _B64) + "." + _rand_str(rng, 40, _B64)
    return "SENDGRID_API_KEY=%s" % tok, tok, False


def _mk_twilio_sid(rng):
    sid = "AC" + _rand_str(rng, 32, _HEX)
    return "twilio sid %s recorded" % sid, sid, False


def _mk_twilio_token(rng):
    tok = _rand_str(rng, 32, _HEX)
    return "TWILIO_AUTH_TOKEN=%s" % tok, tok, False


def _mk_bearer(rng):
    tok = _rand_str(rng, rng.randint(24, 40), _B64)
    return "Authorization: Bearer %s" % tok, tok, False


def _mk_jwt(rng):
    jwt = "eyJ" + _rand_str(rng, 12, _B64) + "." + _rand_str(rng, 18, _B64) + "." + _rand_str(rng, 24, _B64)
    return "session token %s here" % jwt, jwt, False


def _mk_apikey(rng):
    val = _rand_str(rng, 28, _MIXED)
    return 'api_key="%s"' % val, val, False


def _mk_pem(rng):
    body = _rand_str(rng, 40, _B64)
    seg = ("-----BEGIN PRIVATE KEY-----\nMIIB%s\n%s\n-----END PRIVATE KEY-----"
           % (_rand_str(rng, 20, _B64), body))
    return seg, body, False


def _mk_known_prose(rng):
    tok = _rand_str(rng, 16, _MIXED)
    return "the shared phrase for this run is %s ok" % tok, tok, True


_SECRET_MAKERS = [_mk_smtp_pass, _mk_sendgrid, _mk_twilio_sid, _mk_twilio_token,
                  _mk_bearer, _mk_jwt, _mk_apikey, _mk_pem, _mk_known_prose]


def gen_scrub_case(rng):
    """Build a text mixing safe (must-survive) non-secret lines + >=1 synthetic secret pattern +
    declared known-secrets, shuffled into a single document."""
    version = gen_version(rng)
    survivor_pool = [
        "Colima Desktop %s released" % version,
        "Version:  %s" % version,
        "Roadmap:  R0, R1, R2, R3 completed",
        "Notes:    https://github.com/juslintek/colima-desktop/releases/tag/%s" % version,
        "RESULT: GREEN (coverage 74.2%, frontends 9/9, test pass)",
        "the build finished and all checks passed cleanly",
    ]
    survivors = rng.sample(survivor_pool, rng.randint(2, len(survivor_pool)))
    segments = list(survivors)

    makers = rng.sample(_SECRET_MAKERS, rng.randint(1, len(_SECRET_MAKERS)))
    injected = []
    known = []
    for mk in makers:
        seg, secret, is_known = mk(rng)
        segments.append(seg)
        injected.append(secret)
        if is_known:
            known.append(secret)

    rng.shuffle(segments)
    return "\n".join(segments), injected, known, survivors


def run_property_25(seed_rng, iters):
    r = PropResult("Property 25 (secret hygiene invariant)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            text, injected, known, survivors = gen_scrub_case(rng)
            scrubbed = scrub.scrub(text, known)

            # 1. NONE of the injected secrets remain in the scrubbed output.
            for s in injected:
                assert s not in scrubbed, "injected secret substring survived scrub"

            # 2. Completeness: assert_clean must not raise, and contains_secret must be False.
            scrub.assert_clean(scrubbed, known)  # raises SecretLeakError if any secret remains
            assert not scrub.contains_secret(scrubbed, known), "contains_secret after scrub"

            # 3. Idempotence: scrub(scrub(x)) == scrub(x).
            assert scrub.scrub(scrubbed, known) == scrubbed, "scrub is not idempotent"

            # 4. Non-secret content survives verbatim.
            for s in survivors:
                assert s in scrubbed, "non-secret content dropped: %r" % s[:48]

            # 5. Something was redacted (>=1 synthetic secret was injected).
            assert scrub.REDACTION_PLACEHOLDER in scrubbed, "expected at least one redaction"

            r.record_pass()
        except SecretLeakError as e:
            r.record_fail({"iter_seed": iseed, "error": "SecretLeakError: %s" % e, "where": _short_tb()})
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Deterministic edge cases (hand-verified) — anchor each property
# --------------------------------------------------------------------------- #
def run_deterministic_checks():
    results = []

    def check(name, fn):
        try:
            fn()
            results.append((name, True, "ok"))
        except Exception as e:
            results.append((name, False, "%r | %s" % (e, _short_tb())))

    # ---- Property 23 anchors ----
    def p23_default():
        s = render.default_v1_summary()
        rr = render.render(s)
        assert rr.email.to == EMAIL_RECIPIENT and rr.sms.to == SMS_RECIPIENT
        assert "v1.0.0" in rr.email.body and "v1.0.0" in rr.sms.text
        for rid in render.DEFAULT_ROADMAP_IDS:
            assert rid in rr.email.body
        assert s.verify_result in rr.email.body and s.verify_result in rr.sms.text

    check("P23 default v1 summary is complete on both channels", p23_default)

    def p23_single_id():
        s = render.NotificationSummary(version="v2.3.4", roadmap_ids=["R7"],
                                       verify_result="RESULT: GREEN")
        rr = render.render(s)
        assert "v2.3.4" in rr.email.body and "R7" in rr.email.body and "RESULT: GREEN" in rr.email.body
        assert "v2.3.4" in rr.sms.text and "RESULT: GREEN" in rr.sms.text

    check("P23 single-roadmap-id summary", p23_single_id)

    def p23_errors():
        assert _raises_render_error(lambda: render.render(render.NotificationSummary("", ["R0"], "x")))
        assert _raises_render_error(lambda: render.render(render.NotificationSummary("v1", [], "x")))
        assert _raises_render_error(lambda: render.render(render.NotificationSummary("v1", ["R0"], "")))
        assert _raises_render_error(lambda: render.render(render.NotificationSummary("v1", ["  "], "x")))

    check("P23 RenderError on missing version / verify / roadmap", p23_errors)

    # ---- Property 24 anchors ----
    def p24_empty_env():
        rendered = render.render(render.default_v1_summary())
        tmp = tempfile.mkdtemp(prefix="notify-det-")
        try:
            res = deliver.deliver_all(rendered, env={}, out_dir=tmp)
            by = {x.channel: x for x in res}
            assert by[EMAIL].status == STATUS_DRAFTED and by[SMS].status == STATUS_DRAFTED
            assert os.path.exists(by[EMAIL].draft_path) and os.path.exists(by[SMS].draft_path)
            assert by[EMAIL].missing_vars and by[SMS].missing_vars
            assert os.path.exists(os.path.join(tmp, deliver.SEND_SCRIPT_NAME))
            assert os.path.exists(os.path.join(tmp, deliver.combined_filename("v1.0.0")))
            et = _read(by[EMAIL].draft_path)
            assert "v1.0.0" in et and EMAIL_RECIPIENT in et
            for rid in render.DEFAULT_ROADMAP_IDS:
                assert rid in et
            assert SMS_RECIPIENT in _read(by[SMS].draft_path)
            # optional channels are not drafted when unconfigured
            assert all(x.channel in (EMAIL, SMS) for x in res)
        finally:
            _rmtree_quiet(tmp)

    check("P24 empty env drafts both required channels + script + json", p24_empty_env)

    def p24_completeness_detection():
        assert deliver.load_email_creds({"SENDGRID_API_KEY": "SG.x"}).complete
        assert deliver.load_email_creds({"SMTP_HOST": "h", "SMTP_USER": "u", "SMTP_PASS": "p"}).complete
        assert not deliver.load_email_creds({"SMTP_HOST": "h"}).complete
        assert not deliver.load_email_creds({}).complete
        assert deliver.load_sms_creds(
            {"TWILIO_ACCOUNT_SID": "AC", "TWILIO_AUTH_TOKEN": "t", "TWILIO_FROM": "+1"}).complete
        assert not deliver.load_sms_creds({"TWILIO_ACCOUNT_SID": "AC"}).complete
        assert not deliver.load_sms_creds({}).complete

    check("P24 credential-completeness detection (SMTP/SendGrid/Twilio)", p24_completeness_detection)

    def p24_forced_draft_no_leak():
        rendered = render.render(render.default_v1_summary())
        # SYNTHETIC complete SMTP set -> email complete; force_draft keeps it offline.
        env = {"SMTP_HOST": "smtp.example.test", "SMTP_USER": "u@example.test",
               "SMTP_PASS": "Pw-synthetic-not-real-000000"}
        tmp = tempfile.mkdtemp(prefix="notify-det2-")
        try:
            assert deliver.load_email_creds(env).complete
            res = deliver.deliver_all(rendered, env=env, out_dir=tmp, force_draft=True)
            by = {x.channel: x for x in res}
            assert by[EMAIL].status == STATUS_DRAFTED, "forced draft even with complete creds"
            assert "Pw-synthetic-not-real-000000" not in _read(by[EMAIL].draft_path), \
                "the synthetic secret must not leak into the forced draft"
        finally:
            _rmtree_quiet(tmp)

    check("P24 forced draft with complete creds does not leak the secret", p24_forced_draft_no_leak)

    # ---- Property 25 anchors ----
    def p25_plain_unchanged():
        plain = "Colima Desktop v1.0.0 released. Roadmap R0..R8 done. Notes https://x/y."
        assert scrub.scrub(plain) == plain and not scrub.contains_secret(plain)

    check("P25 plain non-secret text is unchanged + clean", p25_plain_unchanged)

    def p25_shapes_redacted():
        cases = [
            "SMTP_PASS=Pw-hunter2-not-real-9f8e7d1c2b",
            "SENDGRID_API_KEY=SG." + "A" * 22 + "." + "B" * 40,
            "TWILIO_ACCOUNT_SID=AC" + "0" * 32,
            "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl",
            "url=postgres://user:p4ss-not-real@db:5432/app",
            "-----BEGIN PRIVATE KEY-----\nMIIBVwIBADAN\nkqhkiG9w0\n-----END PRIVATE KEY-----",
        ]
        for c in cases:
            assert not scrub.contains_secret(scrub.scrub(c)), "shape not redacted: %s" % c[:32]

    check("P25 synthetic secret shapes are each redacted", p25_shapes_redacted)

    def p25_known_secret_idempotent_clean():
        ks = ["swordfish-not-real-123"]
        t = "note: the phrase is swordfish-not-real-123 for now"
        sc = scrub.scrub(t, ks)
        assert "swordfish-not-real-123" not in sc
        assert scrub.scrub(sc, ks) == sc
        scrub.assert_clean(sc, ks)

    check("P25 known secret removed + idempotent + assert_clean passes", p25_known_secret_idempotent_clean)

    def p25_no_over_redaction():
        assert "v1.0.0" in scrub.scrub("Version: v1.0.0")
        url = "https://github.com/o/r/releases/tag/v1.0.0"
        assert url in scrub.scrub("Notes: " + url)
        assert not scrub.contains_secret("value = " + scrub.REDACTION_PLACEHOLDER)

    check("P25 no over-redaction of version/URL/placeholder", p25_no_over_redaction)

    return results


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def run_all(iters, seed):
    global _LOG_FH
    _LOG_FH = open(LOG_PATH, "w")
    log("START notify PBT  seed=%d iters=%d  modules=%s" % (seed, iters, NOTIFY_DIR))
    log("Feature: cross-platform-live-verification (Properties 23, 24, 25)")
    log("EMAIL_RECIPIENT=%s  SMS_RECIPIENT=%s" % (EMAIL_RECIPIENT, SMS_RECIPIENT))

    for name in ("render", "deliver", "scrub"):
        if not (NOTIFY_DIR / (name + ".py")).exists():
            log("FATAL: notify module not found: %s.py" % name)
            return 1

    det = run_deterministic_checks()
    det_failed = [d for d in det if not d[1]]
    for name, ok, detail in det:
        log("  [det] %-58s %s%s" % (name, "OK" if ok else "FAIL",
                                    "" if ok else "  (%s)" % detail))
    log("Deterministic checks: %d/%d passed" % (len(det) - len(det_failed), len(det)))

    seed_rng = random.Random(seed)
    results = [
        run_property_23(random.Random(seed_rng.randrange(2 ** 63)), iters),
        run_property_24(random.Random(seed_rng.randrange(2 ** 63)), iters),
        run_property_25(random.Random(seed_rng.randrange(2 ** 63)), iters),
    ]
    for res in results:
        log("  %-52s ran=%d passed=%d failed=%d" % (res.name, res.ran, res.passed, res.failed))

    total_failed = len(det_failed) + sum(res.failed for res in results)
    summary = {
        "seed": seed,
        "iters_per_property": iters,
        "deterministic": {"total": len(det), "failed": len(det_failed),
                          "failures": [d[0] for d in det_failed]},
        "properties": [
            {"name": res.name, "ran": res.ran, "passed": res.passed, "failed": res.failed,
             "counterexamples": res.failures[:5]}
            for res in results
        ],
        "overall": "PASS" if total_failed == 0 else "FAIL",
    }
    with open(SUMMARY_PATH, "w") as fh:
        json.dump(summary, fh, indent=2)
    log("DONE overall=%s total_failures=%d  summary=%s"
        % (summary["overall"], total_failed, SUMMARY_PATH))
    _LOG_FH.close()
    _LOG_FH = None
    return 0 if total_failed == 0 else 1


# --------------------------------------------------------------------------- #
# pytest entry points (min 100 iterations enforced)
# --------------------------------------------------------------------------- #
_PYTEST_ITERS = max(100, int(os.environ.get("NOTIFY_PBT_ITERS", "150")))
_PYTEST_SEED = int(os.environ.get("NOTIFY_PBT_SEED", "1310"))


def test_property_23_notification_rendering_completeness():
    """Feature: cross-platform-live-verification, Property 23."""
    r = run_property_23(random.Random(_PYTEST_SEED), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "rendering-completeness counterexamples: %r" % r.failures[:5]


def test_property_24_credentials_absent_fallback():
    """Feature: cross-platform-live-verification, Property 24."""
    r = run_property_24(random.Random(_PYTEST_SEED + 1), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "credentials-absent-fallback counterexamples: %r" % r.failures[:5]


def test_property_25_secret_hygiene_invariant():
    """Feature: cross-platform-live-verification, Property 25."""
    r = run_property_25(random.Random(_PYTEST_SEED + 2), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "secret-hygiene counterexamples: %r" % r.failures[:5]


def test_deterministic_edge_cases():
    det = run_deterministic_checks()
    failed = [(d[0], d[2]) for d in det if not d[1]]
    assert not failed, "deterministic edge case failures: %r" % failed


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description="Property tests for scripts/notify/{render,deliver,scrub}.py")
    ap.add_argument("--iters", type=int, default=150,
                    help="randomized iterations per property (min 100 enforced)")
    ap.add_argument("--seed", type=int,
                    default=int(os.environ.get("NOTIFY_PBT_SEED", str(int(time.time())))))
    args = ap.parse_args()
    iters = max(100, args.iters)
    sys.exit(run_all(iters, args.seed))


if __name__ == "__main__":
    main()
