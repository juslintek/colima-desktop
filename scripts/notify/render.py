#!/usr/bin/env python3
"""
render.py -- completion-notification RENDERER for the Cross-Platform Live Verification
program (R13 / task 14.1, Requirements 13.1, 13.2, 13.3; design Property 23).

This module owns exactly ONE responsibility: turn a structured completion `NotificationSummary`
into the per-channel rendered payloads the release-completion notification requires --

    render(summary) -> RenderedNotification{email, sms}

per the design "Notification service -- scripts/notify/" interface:

    render(summary: {version, roadmap_ids[], verify_result, notes_url}) -> {email, sms}

Requirement mapping (design.md -> "Notification Service Design (R13)"):
  * R13.1 -- the EMAIL carries the released version, the completed roadmap item identifiers,
             and the final verification result (recipient jusys.linas@gmail.com).
  * R13.2 -- the SMS carries the released version and the final verification result
             (recipient +37060891909).
  * R13.3 -- credentials come from the ENVIRONMENT only. This renderer NEVER reads, holds, or
             emits a credential: recipients are the fixed values from the requirements, and the
             payload types below carry NO credential/secret field by construction (design
             `NotificationPayload` "no credential/secret field ... by construction", R13.6 /
             Property 25). Delivery (task 14.2) reads the env-var credentials; the secret-hygiene
             scrub (task 14.3) asserts no secret substring leaks. Both consume what render() emits.

design Property 23 (Notification rendering completeness, Requirements 13.1/13.2): *for any*
completion summary, the rendered email contains the released version, ALL completed roadmap item
identifiers, and the final verification result; and the rendered SMS contains the released version
and the final verification result. `render_email`/`render_sms`/`render` are pure and total over a
non-empty summary so the task-14.4 property test can drive them directly.

OWNERSHIP / integration note (disjoint-path concurrency): task 14.1 owns ONLY this rendering module.
The rendering TYPES (`NotificationSummary`, `EmailPayload`, `SmsPayload`, `RenderedNotification`) are
defined LOCALLY here rather than in a shared package, so 14.1 and the concurrently-running 14.2
(deliver) / 14.3 (scrub) never edit the same file. Task 14.2 (channel delivery) will reconcile these
local payload types into the shared delivery contract when it integrates. The pure functions are
import-safe (no side effects at import) so the 14.4 property tests can load this file by path (its
name has no hyphen, so a plain `import render` also works once on the path).

The message content summarizes what v1.0.0 accomplished using ONLY the recorded program facts
(all platforms release-engineered; live cross-platform verification against a real Colima backend
on profile `desktop-e2e`: 52 checks passed / 0 failed / 21 withheld, 0 crashes, with a real
container, network, and volume created and removed; CI green across macOS/Windows/Linux with the
release pipeline gated on all-green; honest credential-gated signing). Nothing beyond those facts is
invented, and every dynamic value is a parameter of `NotificationSummary` -- not hardcoded.

Usage:
    python3 scripts/notify/render.py                         # render the v1.0.0 sample, both channels (text)
    python3 scripts/notify/render.py --channel email         # only the rendered email
    python3 scripts/notify/render.py --channel sms           # only the rendered SMS
    python3 scripts/notify/render.py --format json           # machine-readable {email, sms}
    python3 scripts/notify/render.py --version v1.2.3 \
        --roadmap R0,R1,R2 --verify-result "RESULT: GREEN" --notes-url https://example/tag
    python3 scripts/notify/render.py --selftest              # prove Property-23 completeness, exit 0/1
    python3 scripts/notify/render.py -h | --help

This file deliberately avoids `from __future__ import annotations` so its dataclasses resolve
correctly when the module is loaded by path via importlib (mirrors scripts/gen-truth-table.py).
"""

import argparse
import json
import sys
from dataclasses import dataclass, field

# --- Fixed, non-secret constants (from Requirement 13.1/13.2 + the program facts) ----------------
#
# Recipients are the FIXED values named in the requirements -- public contact addresses, NOT
# secrets. Credentials (SMTP/SendGrid/Twilio/... tokens) are read from the environment by the
# delivery step (task 14.2), never here.
EMAIL_RECIPIENT = "jusys.linas@gmail.com"          # Requirement 13.1
SMS_RECIPIENT = "+37060891909"                     # Requirement 13.2

# Public repository slug -> the default release-notes/tag URL (derived, not a secret).
REPO_SLUG = "juslintek/colima-desktop"
DEFAULT_VERSION = "v1.0.0"

# The roadmap waves completed for v1.0.0 (design "Message content" example: R0..R8 completed).
DEFAULT_ROADMAP_IDS = ("R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8")

# The final verification result, composed ONLY from the recorded program facts (kept as a single
# concise line so it embeds cleanly in BOTH the email and the compact SMS -- Property 23).
DEFAULT_VERIFY_RESULT = (
    "RESULT: GREEN -- live cross-platform verification on profile desktop-e2e: "
    "52 checks passed, 0 failed, 21 withheld, 0 crashes; "
    "CI green across macOS/Windows/Linux (rc-gate + release-gate + per-OS builds)"
)

# One-line headline summarizing what was accomplished (program facts only).
DEFAULT_HEADLINE = (
    "Colima Desktop {version} has been release-engineered across all platforms: "
    "macOS (SwiftUI), Windows (WinUI 3), Linux (GTK 4), a Bubble Tea TUI, and a Go/gRPC daemon."
)

# Accomplishment highlights for the email body (program facts only; no invention).
DEFAULT_HIGHLIGHTS = (
    "Live cross-platform verification ran against a real Colima backend (profile desktop-e2e): "
    "52 checks passed, 0 failed, 21 withheld, 0 crashes.",
    "A real container, network, and volume were created and removed successfully.",
    "CI is green across macOS, Windows, and Linux; the release pipeline is gated on all-green "
    "(rc-gate + release-gate + per-OS build jobs).",
    "Artifacts are credential-gated and labeled unsigned where signing credentials are absent "
    "(Apple Developer ID / notary / Windows / Linux certs). The Sparkle appcast signing key is present.",
)

SUBJECT_TEMPLATE = "Colima Desktop {version} released"


class RenderError(ValueError):
    """Raised when a summary cannot be rendered (missing version / verify result / roadmap ids)."""


# --- Rendering types (defined LOCALLY; 14.2 reconciles into the shared delivery contract) --------


@dataclass(frozen=True)
class NotificationSummary:
    """Structured completion input -- the design `NotificationPayload`, extended with the
    accomplishment fields the message summary needs. NO credential/secret field exists here by
    construction (R13.6 / Property 25)."""

    version: str
    roadmap_ids: list[str]
    verify_result: str
    notes_url: str = ""
    headline: str = ""
    highlights: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class EmailPayload:
    """Rendered email channel payload. Secret-free by construction (only a public recipient +
    rendered text)."""

    to: str
    subject: str
    body: str

    def as_dict(self) -> dict:
        return {"to": self.to, "subject": self.subject, "body": self.body}


@dataclass(frozen=True)
class SmsPayload:
    """Rendered SMS channel payload. Secret-free by construction."""

    to: str
    text: str

    def as_dict(self) -> dict:
        return {"to": self.to, "text": self.text}


@dataclass(frozen=True)
class RenderedNotification:
    """The `{email, sms}` product of render()."""

    email: EmailPayload
    sms: SmsPayload

    def as_dict(self) -> dict:
        return {"email": self.email.as_dict(), "sms": self.sms.as_dict()}


# --- Pure helpers --------------------------------------------------------------------------------


def notes_url_for(version: str) -> str:
    """Default release-notes/tag URL for a version (derived from the public repo slug)."""
    return "https://github.com/%s/releases/tag/%s" % (REPO_SLUG, version)


def format_roadmap(roadmap_ids) -> str:
    """Join the roadmap identifiers into the human-readable list used in the email."""
    return ", ".join(roadmap_ids)


def _clean_ids(roadmap_ids) -> list[str]:
    """Normalize an iterable of roadmap ids to a list of non-empty, stripped strings."""
    out: list[str] = []
    for rid in roadmap_ids or []:
        text = str(rid).strip()
        if text:
            out.append(text)
    return out


def default_v1_summary(
    version: str = DEFAULT_VERSION,
    roadmap_ids=DEFAULT_ROADMAP_IDS,
    verify_result: str = DEFAULT_VERIFY_RESULT,
    notes_url: str = "",
) -> NotificationSummary:
    """Build the default v1.0.0 completion summary from the recorded program facts.

    Every value is a parameter so callers (the release step / tests) can override any field; the
    defaults encode ONLY the recorded facts. `notes_url` defaults to the derived tag URL.
    """
    ids = _clean_ids(roadmap_ids)
    return NotificationSummary(
        version=version,
        roadmap_ids=ids,
        verify_result=verify_result,
        notes_url=notes_url or notes_url_for(version),
        headline=DEFAULT_HEADLINE.format(version=version),
        highlights=list(DEFAULT_HIGHLIGHTS),
    )


def _require(value: str, field_name: str) -> str:
    text = (value or "").strip()
    if not text:
        raise RenderError("notification summary is missing a non-empty %s" % field_name)
    return text


def render_email(summary: NotificationSummary, recipient: str = EMAIL_RECIPIENT) -> EmailPayload:
    """Render the EMAIL payload (Requirement 13.1): version + ALL roadmap ids + verify result.

    The body also carries the headline, notes URL, and accomplishment highlights (the "what was
    accomplished" summary). Recipient is the fixed value; no credential is read.
    """
    version = _require(summary.version, "version")
    verify_result = _require(summary.verify_result, "verify_result")
    ids = _clean_ids(summary.roadmap_ids)
    if not ids:
        raise RenderError("email requires at least one completed roadmap id (Requirement 13.1)")

    notes_url = summary.notes_url.strip() or notes_url_for(version)
    headline = summary.headline.strip() or DEFAULT_HEADLINE.format(version=version)
    highlights = [h.strip() for h in (summary.highlights or []) if h and h.strip()]

    lines = [headline, ""]
    lines.append("Version:  %s" % version)
    lines.append("Roadmap:  %s completed" % format_roadmap(ids))
    lines.append("Verify:   %s" % verify_result)
    lines.append("Notes:    %s" % notes_url)
    if highlights:
        lines.append("")
        lines.append("Highlights:")
        for item in highlights:
            lines.append("  - %s" % item)

    return EmailPayload(
        to=recipient,
        subject=SUBJECT_TEMPLATE.format(version=version),
        body="\n".join(lines),
    )


def render_sms(summary: NotificationSummary, recipient: str = SMS_RECIPIENT) -> SmsPayload:
    """Render the compact SMS payload (Requirement 13.2): version + final verification result only."""
    version = _require(summary.version, "version")
    verify_result = _require(summary.verify_result, "verify_result")
    return SmsPayload(
        to=recipient,
        text="Colima Desktop %s released. %s" % (version, verify_result),
    )


def render(
    summary: NotificationSummary,
    email_recipient: str = EMAIL_RECIPIENT,
    sms_recipient: str = SMS_RECIPIENT,
) -> RenderedNotification:
    """Render both channels from a completion summary (design `render(summary) -> {email, sms}`).

    Pure + total over a non-empty summary; raises RenderError on a missing version / verify result /
    roadmap id. Emits NO credential (Property 25 structural exclusion) -- delivery (14.2) supplies
    credentials from the environment.
    """
    return RenderedNotification(
        email=render_email(summary, recipient=email_recipient),
        sms=render_sms(summary, recipient=sms_recipient),
    )


# --- CLI -----------------------------------------------------------------------------------------


def _summary_from_args(args) -> NotificationSummary:
    roadmap_ids = DEFAULT_ROADMAP_IDS
    if args.roadmap:
        roadmap_ids = [part for part in args.roadmap.split(",")]
    return default_v1_summary(
        version=args.version,
        roadmap_ids=roadmap_ids,
        verify_result=args.verify_result if args.verify_result else DEFAULT_VERIFY_RESULT,
        notes_url=args.notes_url or "",
    )


def _render_text(rendered: RenderedNotification, channel: str) -> str:
    blocks: list[str] = []
    if channel in ("both", "email"):
        blocks.append("=== EMAIL ===")
        blocks.append("To:      %s" % rendered.email.to)
        blocks.append("Subject: %s" % rendered.email.subject)
        blocks.append("")
        blocks.append(rendered.email.body)
    if channel in ("both", "sms"):
        if blocks:
            blocks.append("")
        blocks.append("=== SMS ===")
        blocks.append("To:   %s" % rendered.sms.to)
        blocks.append("Text: %s" % rendered.sms.text)
    return "\n".join(blocks)


def _selftest() -> int:
    """Prove Property 23 completeness on the default summary + a couple of overrides. Exit 0/1."""
    print("== notify/render --selftest (Property 23: rendering completeness) ==")
    ok = True
    cases = [
        default_v1_summary(),
        default_v1_summary(version="v1.2.3", roadmap_ids=["R0", "R7", "R13"],
                           verify_result="RESULT: GREEN (all gates pass)"),
    ]
    for i, summary in enumerate(cases):
        rendered = render(summary)
        checks = [
            ("email contains version", summary.version in rendered.email.body),
            ("email contains verify_result", summary.verify_result in rendered.email.body),
            ("email contains every roadmap id",
             all(rid in rendered.email.body for rid in summary.roadmap_ids)),
            ("email addressed to fixed recipient", rendered.email.to == EMAIL_RECIPIENT),
            ("sms contains version", summary.version in rendered.sms.text),
            ("sms contains verify_result", summary.verify_result in rendered.sms.text),
            ("sms addressed to fixed recipient", rendered.sms.to == SMS_RECIPIENT),
        ]
        for label, passed in checks:
            if not passed:
                ok = False
            print("  case %d  %-38s %s" % (i, label, "PASS" if passed else "FAIL"))
    print("RESULT: selftest %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(add_help=False, description="Render the v1 completion notification.")
    ap.add_argument("--version", default=DEFAULT_VERSION, help="released version tag (default v1.0.0)")
    ap.add_argument("--roadmap", default="", help="comma-separated completed roadmap ids (default R0..R8)")
    ap.add_argument("--verify-result", default="", help="final verification result line")
    ap.add_argument("--notes-url", default="", help="release-notes/tag URL (default derived)")
    ap.add_argument("--channel", choices=("both", "email", "sms"), default="both")
    ap.add_argument("--format", choices=("text", "json"), default="text")
    ap.add_argument("--selftest", action="store_true", help="prove Property-23 completeness, exit 0/1")
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
        rendered = render(_summary_from_args(args))
    except RenderError as exc:
        print("render: ERROR: %s" % exc, file=sys.stderr)
        return 1

    if args.format == "json":
        out = rendered.as_dict()
        if args.channel != "both":
            out = {args.channel: out[args.channel]}
        print(json.dumps(out, indent=2))
    else:
        print(_render_text(rendered, args.channel))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
