#!/usr/bin/env python3
"""
scrub.py -- secret-hygiene SCRUB for the completion-notification service
(R13 / task 14.3, Requirements 8.6 & 13.6; design Property 25).

This module owns exactly ONE responsibility in the notification pipeline: guarantee that no
credential/secret substring can reach a rendered message, an emitted log line, or a committed
evidence artifact. It sits between rendering (task 14.1, `render.py`) and delivery/draft-to-file
(task 14.2) and is applied to any text *before* it is logged, drafted to `dist/notifications/*.txt`,
or transmitted over a channel.

design "Notification Service Design (R13)" / "Components and Interfaces -- scripts/notify/":

    scrub(text, known_secrets[]) -> assert no secret substring present

design Property 25 (Secret hygiene invariant, Requirements 8.6 / 13.6): *for any* rendered
notification message, *any* emitted log line, and *any* committed evidence artifact, no credential
or secret substring is present.

Requirement mapping:
  * R13.6 -- exclude credentials/secrets from message content AND from logs.
  * R8.6  -- keep secrets (and machine data) out of every committed evidence artifact.

Two complementary contracts are provided (see the "Public API" section):

  * scrub(text, known_secrets=()) -> str
        Return a redacted copy of `text`. Every recognized secret shape and every declared
        known-secret substring is replaced with the stable placeholder ``***REDACTED***`` while all
        surrounding, non-secret content and structure is preserved. This is the transform applied
        before write/transmit. It is TOTAL (never raises for str input) and IDEMPOTENT
        (`scrub(scrub(x)) == scrub(x)`).

  * assert_clean(text, known_secrets=()) -> None
        The design's "assert no secret substring present" -- raise `SecretLeakError` if any secret
        substring/shape remains. Used as the pre-write / pre-send tripwire and by the task-14.4
        Property-25 test. Its error message is itself log-safe (it reports categories, lengths and a
        non-reversible sha256 prefix, NEVER the raw secret).

Detection covers, at minimum (design R13.6 + task scope):
  API tokens/keys, passwords, bearer/authorization headers, SMTP (and other URL-embedded)
  credentials, Twilio SID/auth-token shapes, PEM private-key blocks, common vendor tokens
  (AWS/GitHub/Slack/SendGrid/Google/Stripe/JWT), and generic high-entropy ``KEY=VALUE`` /
  ``KEY: VALUE`` secret-like assignments.

Conservative-safe bias: redaction is always preferred over leaking, but the heuristics are scoped so
they do NOT destroy the surrounding message -- assignment rules keep the key and only redact the
value; URL/bearer rules keep the structure and only redact the credential; a generic high-entropy
match fires only on a single token value (never on URLs, versions, or prose). A declared
`known_secret` is always honored (any non-empty, non-whitespace declared secret is removed in full),
because "the caller says this is a secret" is authoritative.

OWNERSHIP / integration note (disjoint-path concurrency): task 14.3 owns ONLY this scrub module. Its
types (`Finding`, `ScrubResult`, `SecretLeakError`) are defined LOCALLY here rather than in a shared
package, so the concurrently-running 14.1 (`render.py`) / 14.2 (deliver) never edit the same file.
Task 14.2 (channel delivery) will reconcile this scrub contract into the shared delivery path when it
integrates. This module has NO dependency on `render.py` -- it operates on plain strings -- and is
import-safe (no side effects at import), so the task-14.4 property test can load it by path (its name
has no hyphen, so a plain ``import scrub`` also works once it is on the path).

Like `render.py`/`gen-truth-table.py`, this file deliberately avoids `from __future__ import
annotations` so its dataclasses resolve when loaded by path via importlib, and it is dependency-free
(standard library only).

Usage:
    printf '%s' "$TEXT" | python3 scripts/notify/scrub.py              # redact stdin -> stdout
    python3 scripts/notify/scrub.py --check < message.txt             # exit 0 clean / 3 leak
    python3 scripts/notify/scrub.py --known-secret-env SMTP_PASS ...  # also redact env-var values
    python3 scripts/notify/scrub.py --demo                            # synthetic before/after proof
    python3 scripts/notify/scrub.py --selftest                        # prove the invariants, exit 0/1
    python3 scripts/notify/scrub.py -h | --help
"""

import argparse
import hashlib
import math
import os
import re
import sys
from dataclasses import dataclass

# --- Stable redaction placeholder ----------------------------------------------------------------
#
# Chosen so it can never itself be re-matched as a secret (contains '*', which is outside every
# token charset below) -- this is what makes scrub() idempotent.
REDACTION_PLACEHOLDER = "***REDACTED***"

# Generic high-entropy KEY=VALUE detection thresholds (only the *value* is inspected).
_HIGH_ENTROPY_MIN_LEN = 20      # real API keys/tokens are long; avoids nuking short low-risk values
_HIGH_ENTROPY_MIN_BITS = 3.2    # Shannon bits/char; random base64/hex clears this, English words do not

# Trailing punctuation trimmed from a bare (unquoted) assignment value so we redact the token and
# keep sentence/structure punctuation (e.g. `key=abc.` -> `key=***REDACTED***.`).
_TRAILING_PUNCT = ".,;:!?)]}>\"'"


class SecretLeakError(Exception):
    """Raised by assert_clean() when a secret substring/shape remains in the text.

    The message is LOG-SAFE by construction: it lists each finding's category, length, and a
    non-reversible sha256 prefix -- never the raw secret (Property 25 covers logs too)."""


@dataclass(frozen=True)
class Finding:
    """A detected secret span. Deliberately stores NO raw secret -- only a category, the length, and
    a short non-reversible fingerprint -- so a Finding is itself safe to log or serialize."""

    category: str
    length: int
    fingerprint: str   # first 12 hex chars of sha256(secret); one-way, not the secret
    start: int
    end: int

    def describe(self) -> str:
        return "%s (len=%d, sha256=%s) at [%d:%d]" % (
            self.category, self.length, self.fingerprint, self.start, self.end)


@dataclass(frozen=True)
class ScrubResult:
    """Result of scrub_result(): the redacted text plus log-safe statistics."""

    text: str
    redactions: int
    categories: tuple   # tuple[str, ...] of the categories redacted (order of appearance)


# --- Recognized secret shapes --------------------------------------------------------------------
#
# Each "detector" contributes zero or more secret spans. For a regex detector, `group` names the
# capture that is the secret (None => the whole match is the secret); the rest of the match is
# preserved so structure survives (e.g. the `Authorization: Bearer ` prefix, the `scheme://user:`
# and `@host` around a URL password).

_PEM_RE = re.compile(
    r"-----BEGIN(?:[A-Z0-9 ]+)? ?PRIVATE KEY-----[\s\S]*?-----END(?:[A-Z0-9 ]+)? ?PRIVATE KEY-----")

# JSON Web Token: header.payload.signature, each url-safe base64.
_JWT_RE = re.compile(r"\beyJ[A-Za-z0-9_\-]{4,}\.[A-Za-z0-9_\-]{4,}\.[A-Za-z0-9_\-]{4,}")

# URL-embedded credentials: scheme://user:PASSWORD@host  (covers SMTP/postgres/https/... creds).
_URL_CRED_RE = re.compile(
    r"(?P<pre>[A-Za-z][A-Za-z0-9+.\-]*://[^\s:/@]+:)(?P<secret>[^\s/@]+)(?P<post>@)")

# Authorization header with a scheme: keep the header + scheme word, redact the credential.
_AUTH_HEADER_RE = re.compile(
    r"(?i)(?P<pre>authorization\s*[:=]\s*)(?P<scheme>bearer|basic|token|digest|apikey)\s+"
    r"(?P<secret>[^\s,;\"']+)")

# Standalone bearer/token credential.
_BEARER_RE = re.compile(r"(?i)\b(?P<scheme>bearer|token)\s+(?P<secret>[A-Za-z0-9._\-+/=]{12,})")

# Common cloud/vendor token shapes (whole match is the secret).
_AWS_AKID_RE = re.compile(r"\bA(?:KIA|SIA|IDA|ROA|GPA|NPA|NVA|IPA)[A-Z0-9]{16}\b")
_GITHUB_RE = re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b")
_SLACK_RE = re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b")
_SENDGRID_RE = re.compile(r"\bSG\.[A-Za-z0-9_\-]{16,}\.[A-Za-z0-9_\-]{16,}\b")
_GOOGLE_API_RE = re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b")
_STRIPE_RE = re.compile(r"\b(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{10,}\b")
_TWILIO_RE = re.compile(r"\b(?:AC|SK|AP|IM|MG|PN|CA)[0-9a-fA-F]{32}\b")

# (category, compiled_regex, secret_group_or_None)
_DETECTORS = (
    ("pem-private-key", _PEM_RE, None),
    ("jwt", _JWT_RE, None),
    ("url-credentials", _URL_CRED_RE, "secret"),
    ("authorization-header", _AUTH_HEADER_RE, "secret"),
    ("bearer-token", _BEARER_RE, "secret"),
    ("aws-access-key-id", _AWS_AKID_RE, None),
    ("github-token", _GITHUB_RE, None),
    ("slack-token", _SLACK_RE, None),
    ("sendgrid-key", _SENDGRID_RE, None),
    ("google-api-key", _GOOGLE_API_RE, None),
    ("stripe-key", _STRIPE_RE, None),
    ("twilio-sid", _TWILIO_RE, None),
)

# KEY=VALUE / KEY: VALUE assignment. VALUE is a double/single-quoted string or a bare token.
_ASSIGNMENT_RE = re.compile(
    r'(?P<key>[A-Za-z][A-Za-z0-9_.\-]*)\s*[:=]\s*'
    r'(?P<val>"[^"\n]*"|\'[^\'\n]*\'|[^\s,;]+)')

# Normalized (lowercased, separators stripped) key markers that make a value secret-like regardless
# of its entropy. Chosen to avoid common innocent keys.
_SECRET_KEY_MARKERS = (
    "password", "passwd", "passphrase", "passcode",
    "secret", "apikey", "apitoken", "accesskey", "secretkey", "privatekey",
    "clientsecret", "authtoken", "authkey", "accesstoken",
    "refreshtoken", "idtoken", "sessiontoken", "sessionkey", "bearer", "token",
    "credential", "sendgrid", "smtppass", "smtppassword", "twilioauthtoken",
    "webhooksecret", "signingsecret", "signingkey", "encryptionkey", "cookie",
)

# Charset a bare high-entropy token value must consist of entirely (no '.'/':' -> excludes URLs,
# dotted versions, and hostnames from the generic high-entropy path).
_TOKEN_CHARSET_RE = re.compile(r"[A-Za-z0-9+/=_\-]+")


def _shannon_entropy(s: str) -> float:
    """Shannon entropy of `s` in bits per character."""
    if not s:
        return 0.0
    counts = {}
    for ch in s:
        counts[ch] = counts.get(ch, 0) + 1
    n = len(s)
    return -sum((c / n) * math.log2(c / n) for c in counts.values())


def _is_secret_key(key: str) -> bool:
    """True if a KEY name marks its value as secret-like (normalized substring match)."""
    norm = re.sub(r"[^a-z0-9]", "", key.lower())
    return any(marker in norm for marker in _SECRET_KEY_MARKERS)


def _looks_high_entropy(value: str) -> bool:
    """True if a bare assignment VALUE looks like a secret token (long, mixed, high entropy).

    Excludes URLs/versions/hostnames (anything with '://' or characters outside the token charset)
    so it never redacts a release-notes URL or a version string."""
    if len(value) < _HIGH_ENTROPY_MIN_LEN:
        return False
    if "://" in value:
        return False
    if not _TOKEN_CHARSET_RE.fullmatch(value):
        return False
    classes = 0
    if any(c.islower() for c in value):
        classes += 1
    if any(c.isupper() for c in value):
        classes += 1
    if any(c.isdigit() for c in value):
        classes += 1
    if any(c in "+/=-_" for c in value):
        classes += 1
    if classes < 2:
        return False
    return _shannon_entropy(value) >= _HIGH_ENTROPY_MIN_BITS


def _unwrap_quotes(raw: str):
    """Return (inner, quote_len): strip a single matching pair of surrounding quotes."""
    if len(raw) >= 2 and raw[0] in "\"'" and raw[-1] == raw[0]:
        return raw[1:-1], 1
    return raw, 0


def _assignment_spans(text: str):
    """Yield (start, end, category) for the VALUE of each secret-like assignment.

    Fires when the key is secret-like (any length value) OR the bare value looks high-entropy. Only
    the value is spanned, so the key and separator are preserved."""
    for m in _ASSIGNMENT_RE.finditer(text):
        key = m.group("key")
        raw = m.group("val")
        vstart, vend = m.span("val")
        inner, qlen = _unwrap_quotes(raw)
        istart = vstart + qlen
        iend = vend - qlen
        if qlen == 0:
            trimmed = inner.rstrip(_TRAILING_PUNCT)
            iend = istart + len(trimmed)
            inner = trimmed
        if not inner or istart >= iend:
            continue
        if REDACTION_PLACEHOLDER in inner:
            continue
        if _is_secret_key(key):
            yield (istart, iend, "secret-assignment")
        elif _looks_high_entropy(inner):
            yield (istart, iend, "high-entropy-assignment")


def _detector_spans(text: str):
    """Yield (start, end, category) for every recognized secret shape (regex detectors)."""
    for category, regex, group in _DETECTORS:
        for m in regex.finditer(text):
            if group is None:
                start, end = m.start(), m.end()
            else:
                if m.group(group) is None:
                    continue
                start, end = m.span(group)
            if start >= end:
                continue
            if REDACTION_PLACEHOLDER in text[start:end]:
                continue
            yield (start, end, category)


def _usable_known_secrets(known_secrets):
    """De-duplicated, non-empty, non-whitespace declared secrets, longest-first.

    Longest-first so a shorter secret that is a substring of a longer one never fragments it."""
    seen = set()
    usable = []
    for s in known_secrets or ():
        if s is None:
            continue
        if not isinstance(s, str):
            s = str(s)
        if not s.strip():
            continue
        if s in seen:
            continue
        seen.add(s)
        usable.append(s)
    usable.sort(key=len, reverse=True)
    return usable


def _known_secret_spans(text: str, known_secrets):
    """Yield (start, end, 'known-secret') for every occurrence of each declared secret."""
    for secret in _usable_known_secrets(known_secrets):
        length = len(secret)
        idx = text.find(secret)
        while idx != -1:
            if REDACTION_PLACEHOLDER not in text[idx:idx + length]:
                yield (idx, idx + length, "known-secret")
            idx = text.find(secret, idx + 1)


def _merge_spans(spans):
    """Merge overlapping/touching spans into their union (keeps the first category), sorted."""
    ordered = sorted(spans, key=lambda s: (s[0], -s[1]))
    merged = []
    for start, end, category in ordered:
        if merged and start <= merged[-1][1]:
            prev_start, prev_end, prev_cat = merged[-1]
            merged[-1] = (prev_start, max(prev_end, end), prev_cat)
        else:
            merged.append((start, end, category))
    return merged


def _all_spans(text: str, known_secrets):
    """All secret spans (declared + recognized shapes), merged and non-overlapping."""
    spans = []
    spans.extend(_known_secret_spans(text, known_secrets))
    spans.extend(_detector_spans(text))
    spans.extend(_assignment_spans(text))
    return _merge_spans(spans)


def _require_str(text, name="text"):
    if text is None:
        return ""
    if not isinstance(text, str):
        raise TypeError("%s must be a str, got %s" % (name, type(text).__name__))
    return text


# --- Public API ----------------------------------------------------------------------------------


def find_secrets(text, known_secrets=()):
    """Return a list of log-safe `Finding`s for every secret span in `text`.

    Findings carry NO raw secret (only category/length/fingerprint), so the list itself is safe to
    log or serialize."""
    text = _require_str(text)
    findings = []
    for start, end, category in _all_spans(text, known_secrets):
        segment = text[start:end]
        fingerprint = hashlib.sha256(segment.encode("utf-8", "replace")).hexdigest()[:12]
        findings.append(Finding(category=category, length=len(segment),
                                 fingerprint=fingerprint, start=start, end=end))
    return findings


def contains_secret(text, known_secrets=()):
    """True if any secret substring/shape is present in `text`."""
    return bool(find_secrets(text, known_secrets))


def scrub_result(text, known_secrets=()):
    """Redact `text` and return a `ScrubResult` (redacted text + log-safe stats)."""
    text = _require_str(text)
    spans = _all_spans(text, known_secrets)
    working = text
    # Replace right-to-left so earlier indices stay valid.
    for start, end, _category in sorted(spans, key=lambda s: s[0], reverse=True):
        working = working[:start] + REDACTION_PLACEHOLDER + working[end:]
    categories = tuple(category for _s, _e, category in spans)
    return ScrubResult(text=working, redactions=len(spans), categories=categories)


def scrub(text, known_secrets=()):
    """Return a redacted copy of `text` (the transform applied before write/transmit).

    Every recognized secret shape and every declared known-secret substring is replaced with
    ``***REDACTED***``; all other content and structure is preserved. Total for str input and
    idempotent."""
    return scrub_result(text, known_secrets).text


def assert_clean(text, known_secrets=()):
    """Raise `SecretLeakError` if any secret substring/shape remains in `text`.

    This is the design's "assert no secret substring present" tripwire (Property 25). The error
    message is log-safe (categories/lengths/fingerprints only)."""
    findings = find_secrets(text, known_secrets)
    if findings:
        detail = "; ".join(f.describe() for f in findings)
        raise SecretLeakError(
            "%d secret substring(s) present and must be scrubbed before write/transmit: %s"
            % (len(findings), detail))


# --- CLI -----------------------------------------------------------------------------------------


def _collect_known_secrets(args):
    """Gather declared secrets from --known-secret (values) and --known-secret-env (env-var names).

    Env-var values are read but never echoed; a named-but-unset var is skipped."""
    known = list(args.known_secret or [])
    for name in (args.known_secret_env or []):
        val = os.environ.get(name)
        if val:
            known.append(val)
    return known


def _demo():
    """Print a synthetic before/after demonstration and verify the guarantees. Exit 0/1.

    Uses SYNTHETIC, example-only secret patterns (never real credentials)."""
    sample = (
        "Colima Desktop v1.0.0 released\n"
        "Version:  v1.0.0\n"
        "Roadmap:  R0, R1, R2, R3, R4, R5, R6, R7, R8 completed\n"
        "Verify:   RESULT: GREEN (coverage 74.2%, frontends.yml 9/9, test.yml pass)\n"
        "Notes:    https://github.com/juslintek/colima-desktop/releases/tag/v1.0.0\n"
        "--- diagnostic context that MUST be scrubbed (synthetic values only) ---\n"
        "SMTP_HOST=smtp.example.com\n"
        "SMTP_USER=notifier@example.com\n"
        "SMTP_PASS=hunter2-not-a-real-password-9f8e7d\n"
        "SENDGRID_API_KEY=SG.AAAAAAAAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\n"
        "TWILIO_ACCOUNT_SID=AC00000000000000000000000000000000\n"
        "TWILIO_AUTH_TOKEN=0123456789abcdef0123456789abcdef\n"
        "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.c2lnbmF0dXJlLXZhbHVl\n"
        "db_url=postgres://admin:s3cr3tP%40ss@db.example.com:5432/app\n"
        "aws_key=AKIAIOSFODNN7EXAMPLE\n"
        "github=ghp_0123456789abcdefghijABCDEFGHIJ0123\n"
        "api_token=\"tok_live_Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MA\"\n"
        "custom_note=The build id is XZ9-Qk2 and the shared word is swordfish123\n")
    # `swordfish123` is a plain-prose secret with no recognizable shape -> only the declared
    # known-secret path can remove it (demonstrates that channel).
    known = ["swordfish123", "hunter2-not-a-real-password-9f8e7d"]

    scrubbed = scrub(sample, known)

    print("=== BEFORE (synthetic input) ===")
    print(sample)
    print("=== AFTER (scrubbed) ===")
    print(scrubbed)
    print("=== checks ===")

    must_survive = [
        "Colima Desktop v1.0.0 released",
        "Version:  v1.0.0",
        "R0, R1, R2, R3, R4, R5, R6, R7, R8",
        "RESULT: GREEN (coverage 74.2%, frontends.yml 9/9, test.yml pass)",
        "https://github.com/juslintek/colima-desktop/releases/tag/v1.0.0",
        "Authorization: Bearer",          # header + scheme kept, token redacted
        "postgres://admin:",              # URL structure kept, password redacted
        "XZ9-Qk2",                        # short non-secret token survives
    ]
    must_be_gone = [
        "hunter2-not-a-real-password-9f8e7d",
        "SG.AAAAAAAAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
        "AC00000000000000000000000000000000",
        "0123456789abcdef0123456789abcdef",
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.c2lnbmF0dXJlLXZhbHVl",
        "s3cr3tP%40ss",
        "AKIAIOSFODNN7EXAMPLE",
        "ghp_0123456789abcdefghijABCDEFGHIJ0123",
        "tok_live_Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MA",
        "swordfish123",
    ]
    ok = True
    for phrase in must_survive:
        present = phrase in scrubbed
        ok = ok and present
        print("  survives : %-64s %s" % (phrase[:64], "PASS" if present else "FAIL"))
    for phrase in must_be_gone:
        gone = phrase not in scrubbed
        ok = ok and gone
        print("  redacted : %-64s %s" % (phrase[:64], "PASS" if gone else "FAIL"))

    # The whole scrubbed text must pass the tripwire, and scrub must be idempotent.
    try:
        assert_clean(scrubbed, known)
        clean = True
    except SecretLeakError as exc:
        clean = False
        print("  assert_clean FAILED: %s" % exc)
    ok = ok and clean
    print("  assert_clean(scrubbed) : %s" % ("PASS" if clean else "FAIL"))
    idempotent = scrub(scrubbed, known) == scrubbed
    ok = ok and idempotent
    print("  idempotent             : %s" % ("PASS" if idempotent else "FAIL"))
    print("  redactions applied     : %d" % scrub_result(sample, known).redactions)
    print("RESULT: demo %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def _selftest():
    """Prove the scrub invariants deterministically. Exit 0 on success, 1 on failure."""
    print("== notify/scrub --selftest (Property 25: secret hygiene invariant) ==")
    ok = True

    def check(label, condition):
        nonlocal ok
        if not condition:
            ok = False
        print("  %-52s %s" % (label, "PASS" if condition else "FAIL"))

    # 1. Non-secret text is left untouched.
    plain = "Colima Desktop v1.0.0 released. Roadmap R0..R8 completed. See notes at https://x/y."
    check("non-secret text unchanged", scrub(plain) == plain)
    check("non-secret text is clean", not contains_secret(plain))

    # 2. The placeholder is not itself flagged as a secret (idempotence foundation).
    check("placeholder not flagged", not contains_secret("value = " + REDACTION_PLACEHOLDER))

    # 3. A declared known secret is removed and the text is then clean.
    ks = ["hunter2-not-a-real-password-9f8e7d"]
    leaked = "note: password is hunter2-not-a-real-password-9f8e7d for now"
    scrubbed = scrub(leaked, ks)
    check("known secret removed", ks[0] not in scrubbed)
    check("known secret text clean after scrub", not contains_secret(scrubbed, ks))

    # 4. Recognized shapes (synthetic) are each redacted.
    shape_cases = [
        "SMTP_PASS=hunter2-not-real-9f8e7d1c2b",
        "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.c2ln",
        "AKIAIOSFODNN7EXAMPLE",
        "ghp_0123456789abcdefghijABCDEFGHIJ0123",
        "url=postgres://user:p4ssw0rd-not-real@db:5432/app",
        "AC00000000000000000000000000000000",
        "SG.AAAAAAAAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
        "-----BEGIN PRIVATE KEY-----\nMIIBVwIBADANBg\nkqhki\n-----END PRIVATE KEY-----",
    ]
    for case in shape_cases:
        check("shape redacted: %s" % case[:34], not contains_secret(scrub(case)))

    # 5. Completeness + idempotence over a composite string.
    composite = "\n".join(shape_cases) + "\n" + leaked
    once = scrub(composite, ks)
    check("composite clean after scrub", not contains_secret(once, ks))
    check("scrub is idempotent", scrub(once, ks) == once)

    # 6. A version/URL is NOT redacted (no over-redaction of structure).
    check("version survives", "v1.0.0" in scrub("Version: v1.0.0"))
    check("release URL survives",
          "https://github.com/o/r/releases/tag/v1.0.0"
          in scrub("Notes: https://github.com/o/r/releases/tag/v1.0.0"))

    print("RESULT: selftest %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=False, description="Redact secrets from notification text.")
    ap.add_argument("--text", default=None, help="text to scrub (default: read stdin)")
    ap.add_argument("--check", action="store_true",
                    help="do not transform; exit 0 if clean, 3 if a secret is present")
    ap.add_argument("--known-secret", action="append", default=[],
                    help="a literal secret value to redact (repeatable; prefer --known-secret-env)")
    ap.add_argument("--known-secret-env", action="append", default=[],
                    help="name of an env var whose VALUE should be redacted (repeatable; never echoed)")
    ap.add_argument("--demo", action="store_true", help="synthetic before/after demonstration, exit 0/1")
    ap.add_argument("--selftest", action="store_true", help="prove the invariants, exit 0/1")
    ap.add_argument("-h", "--help", action="store_true")
    try:
        args = ap.parse_args(argv)
    except SystemExit:
        return 2

    if args.help:
        print(__doc__.strip())
        return 0
    if args.demo:
        return _demo()
    if args.selftest:
        return _selftest()

    known = _collect_known_secrets(args)
    text = args.text if args.text is not None else sys.stdin.read()

    if args.check:
        findings = find_secrets(text, known)
        if findings:
            print("scrub: LEAK -- %d secret substring(s) present:" % len(findings), file=sys.stderr)
            for f in findings:
                print("  - %s" % f.describe(), file=sys.stderr)
            return 3
        print("scrub: clean -- no secret substring present", file=sys.stderr)
        return 0

    sys.stdout.write(scrub(text, known))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
