#!/usr/bin/env python3
"""
deliver.py -- completion-notification CHANNEL DELIVERY + credentials-absent fallback for the
Cross-Platform Live Verification program (R13 / task 14.2, Requirements 13.3, 13.4, 13.5, 13.6;
design Property 24).

This module owns exactly ONE responsibility: take the rendered per-channel payloads produced by
`render.py` (task 14.1) and DELIVER them -- either over a real provider when the channel's
credentials are present in the ENVIRONMENT, or, when a required credential is absent/partial, by
DRAFTING the message to a file under `dist/notifications/` plus a re-runnable `send-notifications.sh`
so a human can send it once credentials are exported. It NEVER fails the release when a credential is
absent (design Property 24 / R13.4). It reconciles the local render payload types
(`render.EmailPayload` / `render.SmsPayload`) into a single shared delivery contract
(`OutboundMessage`) and applies the secret-hygiene scrub (task 14.3, `scrub.py`) to every byte before
it is logged, drafted, or transmitted (R13.6 / Property 25).

design "Notification Service Design (R13)" -- interface:

    deliver(channel, payload, env) -> Result{status: sent|drafted, path?}

design "Credential model (env-var only)" -- credentials come from environment variables ONLY; none
are stored in the repo (Assumption A1, R13.3). The provider set per channel (flags/env win):

    email  : SENDGRID_API_KEY                                  (SendGrid)      -- OR --
             SMTP_HOST + SMTP_USER + SMTP_PASS (+ optional SMTP_PORT, SMTP_FROM)  (SMTP)
    sms    : TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN + TWILIO_FROM              (Twilio or equivalent)
    whatsapp (optional): TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN + TWILIO_WHATSAPP_FROM
    telegram (optional): TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
    viber    (optional): VIBER_AUTH_TOKEN + VIBER_RECEIVER

Fixed recipients come from the requirements via `render.py` (email `jusys.linas@gmail.com`, SMS
`+37060891909`); this module reads NO recipient or credential literal of its own -- it references
credentials by env-var NAME only and never prints a credential value.

design Property 24 (Notification credentials-absent fallback, Requirement 13.4): *for any* subset of
absent email/SMS credentials, the service writes the drafted message content to a file and provides a
send script, and does NOT fail the release for the affected channel. Since no SMTP/Twilio credentials
are configured in this environment, the DRAFT path is the primary exercised path today: a plain
`python3 scripts/notify/deliver.py` writes `dist/notifications/email-v1.0.0.txt`,
`dist/notifications/sms-v1.0.0.txt`, a combined `notifications-v1.0.0.json`, and
`dist/notifications/send-notifications.sh`, and exits 0.

design Property 25 (Secret hygiene invariant, R8.6 / R13.6): the rendered payload structurally
excludes secrets (see `render.NotificationPayload` -- "no credential/secret field ... by
construction"), and this module additionally runs `scrub.assert_clean(...)` before every write/log/
transmit and `scrub.scrub(...)` on every emitted log line, so no credential/secret substring can
reach a log, the drafted file, or the wire.

OWNERSHIP / integration note (disjoint-path concurrency): task 14.2 owns ONLY this delivery module.
Tasks 14.1 (`render.py`) and 14.3 (`scrub.py`) are complete; this module IMPORTS them unchanged and
reconciles their locally-defined payload types into the `OutboundMessage` delivery contract here.
`dist/notifications/**` is generated output (git-ignored via the repo root `/dist/` rule), so no
host-specific drafted content is ever committed. The task-14.4 property tests (Property 24) drive the
pure functions below (`load_creds`, `deliver`, `deliver_all`) directly.

Like `render.py`/`scrub.py`/`gen-truth-table.py`, this file deliberately avoids `from __future__
import annotations` so its dataclasses resolve when loaded by path via importlib, imports its sibling
modules by putting their directory on `sys.path` (their names have no hyphen), and keeps networking
imports lazy so the module is import-safe and dependency-free (standard library only).

Usage:
    python3 scripts/notify/deliver.py                       # deliver v1.0.0 (draft when creds absent)
    python3 scripts/notify/deliver.py --draft               # force the draft path (never transmit)
    python3 scripts/notify/deliver.py --channel email       # only the email channel
    python3 scripts/notify/deliver.py --version v1.2.3 --roadmap R0,R1,R2 --verify-result "RESULT: GREEN"
    python3 scripts/notify/deliver.py --format json         # machine-readable delivery report
    python3 scripts/notify/deliver.py --out-dir /tmp/notif  # write drafts elsewhere
    python3 scripts/notify/deliver.py --selftest            # prove the fallback invariants, exit 0/1
    python3 scripts/notify/deliver.py -h | --help
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass, field

# --- Import the sibling render/scrub modules by putting their directory on sys.path --------------
#
# render.py (task 14.1) renders the payloads; scrub.py (task 14.3) is the secret-hygiene tripwire.
# Their filenames have no hyphen, so a plain import works once their directory is importable. This
# keeps deliver.py import-safe and lets the task-14.4 property test load it by path.
_HERE = os.path.dirname(os.path.abspath(__file__))          # scripts/notify
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import render  # noqa: E402  (sibling module; see path insert above)
import scrub   # noqa: E402  (sibling module; see path insert above)

# --- Paths / channel constants -------------------------------------------------------------------

_REPO_ROOT = os.path.dirname(os.path.dirname(_HERE))        # .../scripts/notify -> repo root
DEFAULT_OUT_DIR = os.path.join(_REPO_ROOT, "dist", "notifications")
SEND_SCRIPT_NAME = "send-notifications.sh"

EMAIL = "email"
SMS = "sms"
WHATSAPP = "whatsapp"
TELEGRAM = "telegram"
VIBER = "viber"

REQUIRED_CHANNELS = (EMAIL, SMS)                # always attempted; draft-fallback on absent creds
OPTIONAL_CHANNELS = (WHATSAPP, TELEGRAM, VIBER)  # attempted only WHERE configured (R13.5)
ALL_CHANNELS = REQUIRED_CHANNELS + OPTIONAL_CHANNELS

# Env-var NAMES whose VALUES are treated as known secrets for the scrub tripwire. Values are read for
# scrubbing only and are NEVER logged or written (scrub records only category/length/fingerprint).
_SECRET_ENV_VARS = (
    "SMTP_PASS", "SENDGRID_API_KEY",
    "TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN",
    "TELEGRAM_BOT_TOKEN", "VIBER_AUTH_TOKEN",
)

STATUS_SENT = "sent"
STATUS_DRAFTED = "drafted"
STATUS_SKIPPED = "skipped"


class DeliveryError(Exception):
    """Raised by a real-send path on failure. Its message is scrubbed before it is ever logged."""


# --- Delivery contract types (reconciles render.EmailPayload / render.SmsPayload) ----------------


@dataclass(frozen=True)
class OutboundMessage:
    """The shared, channel-agnostic delivery unit. Carries only public routing + already-rendered,
    secret-free text (never a credential) -- the reconciliation point for the render payload types."""

    channel: str
    recipient: str
    subject: str        # "" for message-only channels (sms/whatsapp/viber)
    body: str           # email body, or the compact message text

    def as_dict(self) -> dict:
        return {"channel": self.channel, "recipient": self.recipient,
                "subject": self.subject, "body": self.body}


@dataclass(frozen=True)
class ChannelCredentials:
    """The credential state for one channel, derived ONLY from env-var presence. Records env-var
    NAMES (never values) so it is safe to log/serialize."""

    channel: str
    provider: str            # "smtp"|"sendgrid"|"twilio"|"telegram"|"viber"|"" (none)
    complete: bool
    present_vars: tuple = ()   # env-var NAMES present
    missing_vars: tuple = ()   # env-var NAMES required-but-absent (for the primary provider)
    optional: bool = False

    def needs_hint(self) -> str:
        """A human, secret-free hint of what to export to enable this channel."""
        return _NEEDS_HINT.get(self.channel, "set the channel credentials in the environment")


@dataclass(frozen=True)
class DeliveryResult:
    """Result of delivering one channel (design `Result{status, path?}`, extended with log-safe
    context). Contains NO secret."""

    channel: str
    status: str              # sent | drafted | skipped
    provider: str = ""
    recipient: str = ""
    draft_path: str = ""
    missing_vars: tuple = ()
    detail: str = ""

    def as_dict(self) -> dict:
        return {"channel": self.channel, "status": self.status, "provider": self.provider,
                "recipient": self.recipient, "draft_path": self.draft_path,
                "missing_vars": list(self.missing_vars), "detail": self.detail}


# Human, secret-free "what to export" hints (env-var NAMES only).
_NEEDS_HINT = {
    EMAIL: "set SENDGRID_API_KEY, or SMTP_HOST + SMTP_USER + SMTP_PASS (+ optional SMTP_PORT, SMTP_FROM)",
    SMS: "set TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN + TWILIO_FROM",
    WHATSAPP: "set TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN + TWILIO_WHATSAPP_FROM",
    TELEGRAM: "set TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID",
    VIBER: "set VIBER_AUTH_TOKEN + VIBER_RECEIVER",
}


# --- Payload reconciliation (render.* -> OutboundMessage) ----------------------------------------


def message_from_email(email_payload) -> OutboundMessage:
    """Reconcile a `render.EmailPayload` (duck-typed: .to/.subject/.body) into an OutboundMessage."""
    return OutboundMessage(channel=EMAIL, recipient=email_payload.to,
                           subject=email_payload.subject, body=email_payload.body)


def message_from_sms(sms_payload) -> OutboundMessage:
    """Reconcile a `render.SmsPayload` (duck-typed: .to/.text) into an OutboundMessage."""
    return OutboundMessage(channel=SMS, recipient=sms_payload.to, subject="", body=sms_payload.text)


def message_for_optional(channel: str, sms_payload, env=None) -> OutboundMessage:
    """Build the optional-channel message. Optional messaging channels carry the same compact
    summary as the SMS (R13.5 "the same summary"); the recipient is provider-specific and read from
    the environment where one is required (never a literal here)."""
    env = os.environ if env is None else env
    recipient = {
        WHATSAPP: env.get("TWILIO_WHATSAPP_TO", sms_payload.to),
        TELEGRAM: env.get("TELEGRAM_CHAT_ID", ""),
        VIBER: env.get("VIBER_RECEIVER", ""),
    }.get(channel, sms_payload.to)
    return OutboundMessage(channel=channel, recipient=recipient, subject="", body=sms_payload.text)


def build_messages(rendered, channels, env=None) -> list:
    """Reconcile a `render.RenderedNotification` into the OutboundMessages for the requested channels."""
    env = os.environ if env is None else env
    out = []
    for ch in channels:
        if ch == EMAIL:
            out.append(message_from_email(rendered.email))
        elif ch == SMS:
            out.append(message_from_sms(rendered.sms))
        elif ch in OPTIONAL_CHANNELS:
            out.append(message_for_optional(ch, rendered.sms, env))
    return out


# --- Credential detection (env-var only; pure) ---------------------------------------------------


def _present(env, name) -> bool:
    val = env.get(name)
    return bool(val and str(val).strip())


def load_email_creds(env) -> ChannelCredentials:
    """Email credential state. SendGrid (SENDGRID_API_KEY) is preferred when present; otherwise SMTP
    (SMTP_HOST + SMTP_USER + SMTP_PASS, SMTP_PORT optional)."""
    if _present(env, "SENDGRID_API_KEY"):
        return ChannelCredentials(EMAIL, "sendgrid", True, present_vars=("SENDGRID_API_KEY",))
    smtp_required = ("SMTP_HOST", "SMTP_USER", "SMTP_PASS")
    present = tuple(v for v in smtp_required if _present(env, v))
    missing = tuple(v for v in smtp_required if not _present(env, v))
    if not missing:
        extra = tuple(v for v in ("SMTP_PORT", "SMTP_FROM") if _present(env, v))
        return ChannelCredentials(EMAIL, "smtp", True, present_vars=present + extra)
    # Incomplete: report the SMTP shortfall plus the SendGrid alternative as the "missing" set.
    return ChannelCredentials(EMAIL, "", False, present_vars=present,
                              missing_vars=missing + ("SENDGRID_API_KEY",))


def load_sms_creds(env) -> ChannelCredentials:
    """SMS credential state via Twilio (or equivalent): ACCOUNT_SID + AUTH_TOKEN + FROM."""
    required = ("TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_FROM")
    present = tuple(v for v in required if _present(env, v))
    missing = tuple(v for v in required if not _present(env, v))
    complete = not missing
    return ChannelCredentials(SMS, "twilio" if complete else "", complete,
                              present_vars=present, missing_vars=missing)


def _load_optional_creds(channel, env) -> ChannelCredentials:
    """Optional-channel credential state. Optional channels are attempted only WHERE fully configured
    (R13.5); an unconfigured optional channel is not drafted."""
    specs = {
        WHATSAPP: ("twilio", ("TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_WHATSAPP_FROM")),
        TELEGRAM: ("telegram", ("TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID")),
        VIBER: ("viber", ("VIBER_AUTH_TOKEN", "VIBER_RECEIVER")),
    }
    provider, required = specs[channel]
    present = tuple(v for v in required if _present(env, v))
    missing = tuple(v for v in required if not _present(env, v))
    complete = not missing
    return ChannelCredentials(channel, provider if complete else "", complete,
                              present_vars=present, missing_vars=missing, optional=True)


def load_creds(channel, env=None) -> ChannelCredentials:
    """Dispatch credential detection for any channel (design `load_creds(channel, env)`)."""
    env = os.environ if env is None else env
    if channel == EMAIL:
        return load_email_creds(env)
    if channel == SMS:
        return load_sms_creds(env)
    if channel in OPTIONAL_CHANNELS:
        return _load_optional_creds(channel, env)
    raise ValueError("unknown channel: %r" % channel)


def known_secret_values(env=None) -> list:
    """Collect the VALUES of the known secret-bearing env vars (for the scrub tripwire only).

    These values are passed to scrub.scrub/assert_clean so that if a credential ever appeared in a
    message/log it would be caught; the values themselves are never logged or written."""
    env = os.environ if env is None else env
    return [str(env[name]) for name in _SECRET_ENV_VARS if _present(env, name)]


# --- File-name helpers ---------------------------------------------------------------------------


def _safe_version(version) -> str:
    """Filesystem-safe rendering of a version tag for a filename."""
    keep = []
    for ch in str(version):
        keep.append(ch if (ch.isalnum() or ch in "._-") else "_")
    return "".join(keep) or "unknown"


def draft_filename(channel, version) -> str:
    """The draft filename for a channel, e.g. `email-v1.0.0.txt` (matches the verify glob)."""
    return "%s-%s.txt" % (channel, _safe_version(version))


def combined_filename(version) -> str:
    return "notifications-%s.json" % _safe_version(version)


# --- Draft rendering (secret-free by construction; scrubbed + asserted before write) -------------


def render_draft_text(message: OutboundMessage, creds: ChannelCredentials, version: str) -> str:
    """Render the text of a draft file: a clearly-labeled DRAFT header (which env-var credential was
    absent + how to send) followed by the exact rendered message. Contains NO credential value."""
    header = [
        "# DRAFT completion notification -- Colima Desktop %s" % version,
        "# Channel %s -- NOT SENT (required delivery credentials are absent in the environment)"
        % message.channel,
        "# Absent credentials -- %s" % creds.needs_hint(),
        "# To send: export the credentials above, then run dist/notifications/%s" % SEND_SCRIPT_NAME,
        "# Secret-scrubbed before write (Requirement 13.6 / Property 25) -- contains no credentials.",
        "# " + ("-" * 78),
    ]
    lines = list(header)
    if message.subject:
        lines.append("To:      %s" % message.recipient)
        lines.append("Subject: %s" % message.subject)
        lines.append("")
        lines.append(message.body)
    else:
        lines.append("To:   %s" % message.recipient)
        lines.append("Text: %s" % message.body)
    return "\n".join(lines) + "\n"


def _assert_message_clean(message: OutboundMessage, known_secrets) -> None:
    """Tripwire: assert the message subject + body carry no secret substring before any use."""
    scrub.assert_clean(message.subject, known_secrets)
    scrub.assert_clean(message.body, known_secrets)


# --- Side-effecting delivery primitives ----------------------------------------------------------


def _ensure_out_dir(out_dir) -> None:
    os.makedirs(out_dir, exist_ok=True)


def write_draft(message: OutboundMessage, creds: ChannelCredentials, version: str,
                out_dir: str, known_secrets=()) -> str:
    """Write the scrubbed, secret-free draft for a channel and return its path.

    The full draft text is scrubbed and then asserted clean; the file is only written once the
    tripwire passes, so a drafted file can never contain a secret substring."""
    _ensure_out_dir(out_dir)
    text = render_draft_text(message, creds, version)
    text = scrub.scrub(text, known_secrets)          # belt: redact any secret shape
    scrub.assert_clean(text, known_secrets)          # suspenders: refuse to write if anything remains
    path = os.path.join(out_dir, draft_filename(message.channel, version))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def ensure_send_script(out_dir: str, version: str, channels, argv_extra=None) -> str:
    """Emit a re-runnable `send-notifications.sh` that re-invokes this delivery CLI once credentials
    are exported. The script contains NO credentials -- it references them by env-var NAME only."""
    _ensure_out_dir(out_dir)
    rel_deliver = os.path.relpath(os.path.join(_HERE, "deliver.py"), out_dir)
    extra = " ".join(argv_extra or [])
    script = """#!/usr/bin/env bash
# send-notifications.sh -- re-run the Colima Desktop %(version)s completion notification once the
# delivery credentials are exported in the environment. GENERATED by scripts/notify/deliver.py
# (task 14.2). This script contains NO credentials; it reads them from environment variables by NAME.
#
#   email    : export SENDGRID_API_KEY   OR   SMTP_HOST + SMTP_USER + SMTP_PASS (+ SMTP_PORT, SMTP_FROM)
#   sms      : export TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN + TWILIO_FROM
#   whatsapp : export TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN + TWILIO_WHATSAPP_FROM   (optional)
#   telegram : export TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID                            (optional)
#   viber    : export VIBER_AUTH_TOKEN + VIBER_RECEIVER                                (optional)
#
# Any channel whose credentials are still absent is simply re-drafted here (never fails the release).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/%(rel_deliver)s" --version %(version)s%(extra)s "$@"
""" % {"version": version, "rel_deliver": rel_deliver,
       "extra": (" " + extra) if extra else ""}
    path = os.path.join(out_dir, SEND_SCRIPT_NAME)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(script)
    try:
        os.chmod(path, 0o755)
    except OSError:
        pass
    return path


def write_combined_json(results, messages, version: str, out_dir: str, known_secrets=()) -> str:
    """Write a combined, secret-free JSON of the delivery report + drafted message content."""
    _ensure_out_dir(out_dir)
    by_channel = {m.channel: m for m in messages}
    payload = {
        "version": version,
        "generated_by": "scripts/notify/deliver.py",
        "channels": [
            {
                **r.as_dict(),
                "message": by_channel[r.channel].as_dict() if r.channel in by_channel else None,
            }
            for r in results
        ],
    }
    text = json.dumps(payload, indent=2, sort_keys=True)
    text = scrub.scrub(text, known_secrets)
    scrub.assert_clean(text, known_secrets)
    path = os.path.join(out_dir, combined_filename(version))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text + "\n")
    return path


# --- Real-send providers (credential-gated; stdlib only; never log a credential) -----------------
#
# These read credentials from `env` at call time and are only reached when the channel's creds are
# complete and --draft was NOT requested. Networking imports are lazy. On any failure they raise
# DeliveryError with a scrubbed message; the caller then falls back to drafting so the release is
# never blocked (Property 24).


def _send_email(message: OutboundMessage, creds: ChannelCredentials, env) -> None:
    if creds.provider == "sendgrid":
        _send_email_sendgrid(message, env)
    else:
        _send_email_smtp(message, env)


def _send_email_smtp(message: OutboundMessage, env) -> None:
    import smtplib
    import ssl
    from email.message import EmailMessage

    host = env["SMTP_HOST"]
    port = int(str(env.get("SMTP_PORT", "587")).strip() or "587")
    user = env["SMTP_USER"]
    password = env["SMTP_PASS"]
    msg = EmailMessage()
    msg["From"] = env.get("SMTP_FROM", user)
    msg["To"] = message.recipient
    msg["Subject"] = message.subject
    msg.set_content(message.body)
    try:
        context = ssl.create_default_context()
        with smtplib.SMTP(host, port, timeout=30) as client:
            client.starttls(context=context)
            client.login(user, password)
            client.send_message(msg)
    except Exception as exc:  # noqa: BLE001 -- normalize to a scrubbed DeliveryError
        raise DeliveryError(scrub.scrub("SMTP send failed: %s" % exc))


def _send_email_sendgrid(message: OutboundMessage, env) -> None:
    import urllib.request

    key = env["SENDGRID_API_KEY"]
    body = {
        "personalizations": [{"to": [{"email": message.recipient}]}],
        "from": {"email": env.get("SENDGRID_FROM", "no-reply@colima-desktop.local")},
        "subject": message.subject,
        "content": [{"type": "text/plain", "value": message.body}],
    }
    req = urllib.request.Request(
        "https://api.sendgrid.com/v3/mail/send",
        data=json.dumps(body).encode("utf-8"), method="POST",
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    _http_send(req, ok=(200, 201, 202), what="SendGrid")


def _send_sms(message: OutboundMessage, creds: ChannelCredentials, env) -> None:
    _send_twilio_message(message.recipient, message.body,
                         env["TWILIO_FROM"], env, what="Twilio SMS")


def _send_optional(message: OutboundMessage, creds: ChannelCredentials, env) -> None:
    if message.channel == WHATSAPP:
        _send_twilio_message("whatsapp:" + message.recipient, message.body,
                             "whatsapp:" + env["TWILIO_WHATSAPP_FROM"], env, what="Twilio WhatsApp")
    elif message.channel == TELEGRAM:
        _send_telegram(message, env)
    elif message.channel == VIBER:
        _send_viber(message, env)
    else:
        raise DeliveryError("no sender for optional channel %r" % message.channel)


def _send_twilio_message(to, body, from_, env, what) -> None:
    import base64
    import urllib.parse
    import urllib.request

    sid = env["TWILIO_ACCOUNT_SID"]
    token = env["TWILIO_AUTH_TOKEN"]
    data = urllib.parse.urlencode({"To": to, "From": from_, "Body": body}).encode("utf-8")
    auth = base64.b64encode(("%s:%s" % (sid, token)).encode("utf-8")).decode("ascii")
    req = urllib.request.Request(
        "https://api.twilio.com/2010-04-01/Accounts/%s/Messages.json" % sid,
        data=data, method="POST",
        headers={"Authorization": "Basic " + auth,
                 "Content-Type": "application/x-www-form-urlencoded"})
    _http_send(req, ok=(200, 201), what=what)


def _send_telegram(message: OutboundMessage, env) -> None:
    import urllib.parse
    import urllib.request

    token = env["TELEGRAM_BOT_TOKEN"]
    data = urllib.parse.urlencode(
        {"chat_id": env["TELEGRAM_CHAT_ID"], "text": message.body}).encode("utf-8")
    req = urllib.request.Request(
        "https://api.telegram.org/bot%s/sendMessage" % token, data=data, method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    _http_send(req, ok=(200,), what="Telegram")


def _send_viber(message: OutboundMessage, env) -> None:
    import urllib.request

    body = {"receiver": env["VIBER_RECEIVER"], "type": "text", "text": message.body,
            "sender": {"name": "Colima Desktop"}}
    req = urllib.request.Request(
        "https://chatapi.viber.com/pa/send_message",
        data=json.dumps(body).encode("utf-8"), method="POST",
        headers={"X-Viber-Auth-Token": env["VIBER_AUTH_TOKEN"], "Content-Type": "application/json"})
    _http_send(req, ok=(200,), what="Viber")


def _http_send(req, ok, what) -> None:
    """POST an urllib Request; raise a scrubbed DeliveryError on any non-OK/exception. The URL and
    request are never logged (a token may be embedded in a URL for some providers)."""
    import urllib.error
    import urllib.request

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            status = getattr(resp, "status", resp.getcode())
            if status not in ok:
                raise DeliveryError("%s send returned HTTP %s" % (what, status))
    except DeliveryError:
        raise
    except urllib.error.HTTPError as exc:
        raise DeliveryError(scrub.scrub("%s send failed: HTTP %s" % (what, exc.code)))
    except Exception as exc:  # noqa: BLE001 -- normalize + scrub any network/other error
        raise DeliveryError(scrub.scrub("%s send failed: %s" % (what, exc)))


def _send(message: OutboundMessage, creds: ChannelCredentials, env) -> None:
    """Dispatch a real send for a channel whose credentials are complete. Raises DeliveryError."""
    if message.channel == EMAIL:
        _send_email(message, creds, env)
    elif message.channel == SMS:
        _send_sms(message, creds, env)
    elif message.channel in OPTIONAL_CHANNELS:
        _send_optional(message, creds, env)
    else:
        raise DeliveryError("no sender for channel %r" % message.channel)


# --- Core delivery ------------------------------------------------------------------------------


def deliver(channel, message: OutboundMessage, env=None, *, version=render.DEFAULT_VERSION,
            out_dir=DEFAULT_OUT_DIR, known_secrets=None, force_draft=False, log=None) -> DeliveryResult:
    """Deliver ONE channel (design `deliver(channel, payload, env) -> Result{status, path?}`).

    Behavior:
      * Optional channel with absent creds -> SKIPPED (not drafted; only sent WHERE configured, R13.5).
      * Required channel (email/sms) with absent/partial creds, or `force_draft` -> DRAFTED to file.
      * Complete creds and not `force_draft` -> real send; on send failure, fall back to a DRAFT so
        the release is never blocked (Property 24) and the content is preserved for a manual re-send.

    Secret hygiene: the message is asserted clean before any transmit, and the draft path scrubs +
    asserts before writing. Never raises for an absent credential (that is the fallback path)."""
    env = os.environ if env is None else env
    known_secrets = known_secret_values(env) if known_secrets is None else known_secrets
    creds = load_creds(channel, env)

    def _log(line):
        if log is not None:
            log(scrub.scrub(line, known_secrets))

    # Optional channel that is not configured -> skip silently (do not draft optional channels).
    if creds.optional and not creds.complete:
        _log("%s: skipped (optional channel not configured)" % channel)
        return DeliveryResult(channel=channel, status=STATUS_SKIPPED, recipient=message.recipient,
                              missing_vars=creds.missing_vars,
                              detail="optional channel not configured")

    # Tripwire before any use of the message text.
    _assert_message_clean(message, known_secrets)

    if creds.complete and not force_draft:
        try:
            _send(message, creds, env)
            _log("%s: sent via %s to %s" % (channel, creds.provider, message.recipient))
            return DeliveryResult(channel=channel, status=STATUS_SENT, provider=creds.provider,
                                  recipient=message.recipient)
        except DeliveryError as exc:
            # Real send failed -> preserve the message as a draft rather than fail the release.
            path = write_draft(message, creds, version, out_dir, known_secrets)
            detail = scrub.scrub("send failed, drafted instead: %s" % exc, known_secrets)
            _log("%s: %s -> %s" % (channel, detail, path))
            return DeliveryResult(channel=channel, status=STATUS_DRAFTED, provider=creds.provider,
                                  recipient=message.recipient, draft_path=path, detail=detail)

    # Credentials absent/partial (or forced): draft to file (the primary path today).
    path = write_draft(message, creds, version, out_dir, known_secrets)
    reason = "forced draft" if force_draft else ("missing %s" % ", ".join(creds.missing_vars))
    _log("%s: drafted (%s) -> %s" % (channel, reason, path))
    return DeliveryResult(channel=channel, status=STATUS_DRAFTED, provider=creds.provider,
                          recipient=message.recipient, draft_path=path,
                          missing_vars=creds.missing_vars, detail=reason)


def _channels_to_attempt(requested, env) -> list:
    """Resolve which channels to attempt: the required channels always, plus any optional channel
    that is fully configured (R13.5). `requested` may narrow to a single channel."""
    if requested in ALL_CHANNELS:
        return [requested]
    chans = list(REQUIRED_CHANNELS)
    for opt in OPTIONAL_CHANNELS:
        if load_creds(opt, env).complete:
            chans.append(opt)
    return chans


def deliver_all(rendered, env=None, *, version=render.DEFAULT_VERSION, out_dir=DEFAULT_OUT_DIR,
                requested="all", force_draft=False, known_secrets=None, log=None,
                write_script=True, write_json=True, argv_extra=None) -> list:
    """Deliver every requested channel, emitting the send script + combined JSON whenever any channel
    was drafted. Returns the list of DeliveryResult. Never raises for absent credentials."""
    env = os.environ if env is None else env
    known_secrets = known_secret_values(env) if known_secrets is None else known_secrets
    channels = _channels_to_attempt(requested, env)
    messages = build_messages(rendered, channels, env)

    results = []
    for msg in messages:
        results.append(deliver(msg.channel, msg, env, version=version, out_dir=out_dir,
                               known_secrets=known_secrets, force_draft=force_draft, log=log))

    if any(r.status == STATUS_DRAFTED for r in results):
        if write_script:
            ensure_send_script(out_dir, version, channels, argv_extra=argv_extra)
        if write_json:
            write_combined_json(results, messages, version, out_dir, known_secrets)
    return results


# --- Summary building (mirrors render CLI) -------------------------------------------------------


def _summary_from_args(args):
    roadmap_ids = render.DEFAULT_ROADMAP_IDS
    if args.roadmap:
        roadmap_ids = [part for part in args.roadmap.split(",")]
    return render.default_v1_summary(
        version=args.version,
        roadmap_ids=roadmap_ids,
        verify_result=args.verify_result if args.verify_result else render.DEFAULT_VERIFY_RESULT,
        notes_url=args.notes_url or "",
    )


# --- CLI -----------------------------------------------------------------------------------------


def _format_report(results, out_dir, version, fmt) -> str:
    if fmt == "json":
        return json.dumps({
            "version": version,
            "out_dir": out_dir,
            "results": [r.as_dict() for r in results],
        }, indent=2, sort_keys=True)
    lines = ["== Colima Desktop notification delivery (task 14.2 / Requirements 13.3-13.6) =="]
    for r in results:
        if r.status == STATUS_SENT:
            lines.append("  %-9s SENT     via %s to %s" % (r.channel, r.provider, r.recipient))
        elif r.status == STATUS_SKIPPED:
            lines.append("  %-9s skipped  (%s)" % (r.channel, r.detail))
        else:  # drafted
            rel = os.path.relpath(r.draft_path, _REPO_ROOT) if r.draft_path else "(none)"
            note = ("missing %s" % ", ".join(r.missing_vars)) if r.missing_vars else r.detail
            lines.append("  %-9s DRAFTED  -> %s  [%s]" % (r.channel, rel, note))
    drafted = [r for r in results if r.status == STATUS_DRAFTED]
    if drafted:
        lines.append("  send script: %s"
                     % os.path.relpath(os.path.join(out_dir, SEND_SCRIPT_NAME), _REPO_ROOT))
        lines.append("RESULT: %d channel(s) drafted (credentials absent) -- release NOT failed "
                     "(Property 24)." % len(drafted))
    else:
        lines.append("RESULT: all requested channels delivered.")
    return "\n".join(lines)


def _selftest() -> int:
    """Prove the fallback invariants (Property 24 spirit) deterministically. Exit 0/1.

    NOTE: this is a lightweight self-check like render.py/scrub.py --selftest; the release-gating
    randomized Property-24 test is task 14.4."""
    import tempfile

    print("== notify/deliver --selftest (Property 24: credentials-absent fallback) ==")
    ok = True

    def check(label, condition):
        nonlocal ok
        if not condition:
            ok = False
        print("  %-56s %s" % (label, "PASS" if condition else "FAIL"))

    rendered = render.render(render.default_v1_summary())

    # 1. Absent credentials -> both required channels drafted; files exist; no exception.
    tmp = tempfile.mkdtemp(prefix="notify-selftest-")
    try:
        results = deliver_all(rendered, env={}, out_dir=tmp)
        by = {r.channel: r for r in results}
        check("email drafted when creds absent", by[EMAIL].status == STATUS_DRAFTED)
        check("sms drafted when creds absent", by[SMS].status == STATUS_DRAFTED)
        check("email draft file exists", os.path.exists(by[EMAIL].draft_path))
        check("sms draft file exists", os.path.exists(by[SMS].draft_path))
        check("send script emitted", os.path.exists(os.path.join(tmp, SEND_SCRIPT_NAME)))
        check("combined json emitted", os.path.exists(os.path.join(tmp, combined_filename("v1.0.0"))))
        check("optional channels not drafted (unconfigured)",
              all(r.channel in REQUIRED_CHANNELS for r in results))

        # 2. Draft content completeness + secret hygiene.
        email_txt = open(by[EMAIL].draft_path, encoding="utf-8").read()
        sms_txt = open(by[SMS].draft_path, encoding="utf-8").read()
        check("email draft has version", "v1.0.0" in email_txt)
        check("email draft has every roadmap id",
              all(rid in email_txt for rid in render.DEFAULT_ROADMAP_IDS))
        check("email draft has GREEN verify result", "RESULT: GREEN" in email_txt)
        check("email draft addressed to fixed recipient", render.EMAIL_RECIPIENT in email_txt)
        check("sms draft has version", "v1.0.0" in sms_txt)
        check("sms draft addressed to fixed recipient", render.SMS_RECIPIENT in sms_txt)
        check("email draft is secret-clean", not scrub.contains_secret(email_txt))
        check("sms draft is secret-clean", not scrub.contains_secret(sms_txt))
    finally:
        _rmtree_quiet(tmp)

    # 3. A synthetic full email credential set is detected complete; forced draft still drafts.
    fake_env = {"SMTP_HOST": "smtp.example.com", "SMTP_USER": "u@example.com",
                "SMTP_PASS": "synthetic-not-real-pass-0000"}
    check("full SMTP env detected complete", load_email_creds(fake_env).complete)
    check("SendGrid env detected complete", load_email_creds({"SENDGRID_API_KEY": "SG.x"}).complete)
    check("empty env -> email incomplete", not load_email_creds({}).complete)
    check("empty env -> sms incomplete", not load_sms_creds({}).complete)

    tmp2 = tempfile.mkdtemp(prefix="notify-selftest2-")
    try:
        res = deliver(EMAIL, message_from_email(rendered.email), fake_env, out_dir=tmp2,
                      force_draft=True)
        check("force_draft drafts even with complete creds", res.status == STATUS_DRAFTED)
        # The scrub tripwire must not have leaked the synthetic password into the draft.
        drafted = open(res.draft_path, encoding="utf-8").read()
        check("forced draft did not leak the synthetic secret",
              "synthetic-not-real-pass-0000" not in drafted)
    finally:
        _rmtree_quiet(tmp2)

    print("RESULT: selftest %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def _rmtree_quiet(path):
    import shutil
    try:
        shutil.rmtree(path)
    except OSError:
        pass


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(add_help=False, description="Deliver the v1 completion notification.")
    ap.add_argument("--version", default=render.DEFAULT_VERSION, help="released version tag (default v1.0.0)")
    ap.add_argument("--roadmap", default="", help="comma-separated completed roadmap ids (default R0..R8)")
    ap.add_argument("--verify-result", default="", help="final verification result line")
    ap.add_argument("--notes-url", default="", help="release-notes/tag URL (default derived)")
    ap.add_argument("--channel", choices=("all",) + ALL_CHANNELS, default="all",
                    help="limit delivery to one channel (default all)")
    ap.add_argument("--out-dir", default=DEFAULT_OUT_DIR, help="draft output directory")
    ap.add_argument("--draft", "--dry-run", dest="draft", action="store_true",
                    help="force the draft path; never transmit over a real channel")
    ap.add_argument("--format", choices=("text", "json"), default="text")
    ap.add_argument("--selftest", action="store_true", help="prove the fallback invariants, exit 0/1")
    ap.add_argument("-h", "--help", action="store_true")
    try:
        args = ap.parse_args(argv)
    except SystemExit:
        return 2

    if args.help:
        print(__doc__.strip())
        return 0
    if args.selftest:
        return _selftest()

    try:
        rendered = render.render(_summary_from_args(args))
    except render.RenderError as exc:
        print("deliver: ERROR: %s" % exc, file=sys.stderr)
        return 1

    known_secrets = known_secret_values(os.environ)

    def _log(line):
        # Logs go to stderr, already scrubbed by deliver(); scrub again as defense-in-depth.
        print("deliver: " + scrub.scrub(line, known_secrets), file=sys.stderr)

    # Re-run script should reproduce the same summary (pass through non-default summary args).
    argv_extra = []
    if args.roadmap:
        argv_extra += ["--roadmap", args.roadmap]
    if args.verify_result:
        argv_extra += ["--verify-result", args.verify_result]
    if args.notes_url:
        argv_extra += ["--notes-url", args.notes_url]

    try:
        results = deliver_all(rendered, os.environ, version=args.version, out_dir=args.out_dir,
                              requested=args.channel, force_draft=args.draft,
                              known_secrets=known_secrets, log=_log, argv_extra=argv_extra)
    except scrub.SecretLeakError as exc:
        # Fail-closed: a would-be secret leak must never be written/transmitted.
        print("deliver: ERROR: refusing to write/transmit -- %s"
              % scrub.scrub(str(exc), known_secrets), file=sys.stderr)
        return 2

    report = _format_report(results, args.out_dir, args.version, args.format)
    report = scrub.scrub(report, known_secrets)   # final guarantee: nothing secret reaches stdout
    scrub.assert_clean(report, known_secrets)
    print(report)

    # Drafting is a success (release is not failed for the affected channel -- Property 24).
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
