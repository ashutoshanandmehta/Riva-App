#!/usr/bin/env python3
"""Configure Supabase Auth email delivery for the iOS email + password flow.

Applies, via the Supabase Management API:

  * Gmail as custom SMTP,
  * the three email templates the flow depends on, rewritten to send a
    six digit ``{{ .Token }}`` instead of a magic link,
  * OTP length 6 and a one hour expiry (matching the app's copy),
  * a real Site URL, so no auth email ever points at localhost.

Secrets are read from the environment and never written anywhere. Nothing here
touches the database.

    export SUPABASE_ACCESS_TOKEN=sbp_...        # supabase.com/dashboard/account/tokens
    export GMAIL_ADDRESS=you@yourdomain.com
    export GMAIL_APP_PASSWORD=xxxxxxxxxxxxxxxx  # 16 chars, 2FA required
    export TPC_SITE_URL=https://thepeptidecompany.com

    python backend/scripts/configure_supabase_auth.py --check-smtp
    python backend/scripts/configure_supabase_auth.py --show
    python backend/scripts/configure_supabase_auth.py --apply

``--check-smtp`` proves the App Password works *before* it goes anywhere near
Supabase, because GoTrue fails silently on bad SMTP credentials — the send just
never arrives and nothing surfaces in the app.

This is a CLI, so it reports to stdout rather than through the service logger.
"""

from __future__ import annotations

import argparse
import json
import os
import smtplib
import ssl
import sys
import urllib.error
import urllib.request

API_ROOT = "https://api.supabase.com/v1"
DEFAULT_PROJECT_REF = "casmdqfgxoihjisrjsbk"
USER_AGENT = "tpc-auth-configurator/1.0"

SMTP_HOST = "smtp.gmail.com"
SMTP_PORT = 587

# How long a code stays valid. The label is what the email says, and
# `EmailFlowView`'s code screen must say the same thing — change all three
# together or the app promises a window it doesn't have.
OTP_EXPIRY_SECONDS = 900
OTP_EXPIRY_LABEL = "15 minutes"

# Auth emails allowed per hour, project-wide. Supabase defaults this to **2**
# for its shared mailer and does NOT raise it when you attach your own SMTP —
# so without this, the third signup attempt of the hour fails with "email rate
# limit exceeded" no matter how much capacity Gmail has. 30/hour is Supabase's
# own custom-SMTP default and stays clear of Gmail's ~500/day ceiling.
EMAIL_RATE_LIMIT_PER_HOUR = 30

# Fields the API accepts but never reads back, so they can't be verified after
# the PATCH — absence from a GET is expected, not drift.
WRITE_ONLY_KEYS = {"smtp_pass"}


# ---------------------------------------------------------------------------
# Email templates
# ---------------------------------------------------------------------------

# `{{ .Token }}` is the whole point: the app verifies a typed six digit code
# against `auth/v1/verify`, and it registers no URL scheme, so a magic link can
# never reach it. Inline styles only — mail clients strip <style> blocks.
_TEMPLATE = """\
<div style="background:#F6F2E8;padding:32px 24px;font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif">
  <div style="max-width:480px;margin:0 auto;background:#FFFDF7;border-radius:20px;padding:32px">
    <p style="margin:0 0 4px;font-size:11px;letter-spacing:1.5px;text-transform:uppercase;color:#9A7526;font-weight:700">
      The Peptide Company
    </p>
    <h1 style="margin:0 0 12px;font-size:21px;color:#17201B">{heading}</h1>
    <p style="margin:0 0 24px;font-size:15px;line-height:1.5;color:#5C6259">{blurb}</p>
    <div style="background:#F6F2E8;border-radius:14px;padding:18px;text-align:center">
      <span style="font-size:30px;font-weight:700;letter-spacing:6px;color:#1E3325">{{{{ .Token }}}}</span>
    </div>
    <p style="margin:24px 0 0;font-size:13px;line-height:1.5;color:#8B9189">
      The code expires in {expiry}. If you didn't request it, you can ignore this email.
    </p>
  </div>
</div>
"""

TEMPLATES = {
    # requestCode() for an address with no account yet.
    "confirmation": {
        "subject": "Your Peptide Company code",
        "heading": "Confirm your email",
        "blurb": "Enter this code in the app to finish creating your account.",
    },
    # requestCode() for an address that already has one.
    "magic_link": {
        "subject": "Your Peptide Company sign in code",
        "heading": "Your sign in code",
        "blurb": "Enter this code in the app to continue.",
    },
    # requestPasswordReset().
    "recovery": {
        "subject": "Reset your Peptide Company password",
        "heading": "Reset your password",
        "blurb": "Enter this code in the app, then choose a new password.",
    },
}


def desired_config(gmail_address: str, gmail_password: str, site_url: str | None) -> dict:
    """The auth config this flow needs."""
    config: dict[str, object] = {
        "smtp_host": SMTP_HOST,
        "smtp_port": str(SMTP_PORT),
        "smtp_user": gmail_address,
        "smtp_pass": gmail_password,
        # Gmail rejects or rewrites a From that isn't the authenticated account.
        "smtp_admin_email": gmail_address,
        "smtp_sender_name": "The Peptide Company",
        # AuthModel.codeLength is 6; the app's code screen quotes the expiry.
        "mailer_otp_length": 6,
        "mailer_otp_exp": OTP_EXPIRY_SECONDS,
        "rate_limit_email_sent": EMAIL_RATE_LIMIT_PER_HOUR,
    }
    for name, spec in TEMPLATES.items():
        body = _TEMPLATE.format(
            heading=spec["heading"], blurb=spec["blurb"], expiry=OTP_EXPIRY_LABEL
        )
        config[f"mailer_subjects_{name}"] = spec["subject"]
        config[f"mailer_templates_{name}_content"] = body
    if site_url:
        config["site_url"] = site_url
    return config


# ---------------------------------------------------------------------------
# Management API
# ---------------------------------------------------------------------------


def _request(method: str, path: str, token: str, payload: dict | None = None) -> dict:
    body = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        f"{API_ROOT}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            # Cloudflare fronts api.supabase.com and blanket-blocks the default
            # "Python-urllib/3.x" agent with a 1010, so identify ourselves.
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:800]
        raise SystemExit(
            f"Supabase API {method} {path} failed: {error.code} {error.reason}\n{detail}"
        ) from error
    except urllib.error.URLError as error:
        raise SystemExit(f"Could not reach the Supabase API: {error.reason}") from error
    return json.loads(raw) if raw else {}


def get_auth_config(token: str, ref: str) -> dict:
    return _request("GET", f"/projects/{ref}/config/auth", token)


def patch_auth_config(token: str, ref: str, config: dict) -> dict:
    return _request("PATCH", f"/projects/{ref}/config/auth", token, config)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


def summarise(config: dict) -> None:
    """Print the fields that decide whether a code actually arrives."""
    interesting = [
        "external_email_enabled",
        "mailer_autoconfirm",
        "mailer_otp_length",
        "mailer_otp_exp",
        "site_url",
        "smtp_host",
        "smtp_port",
        "smtp_user",
        "smtp_admin_email",
        "smtp_sender_name",
        # The two that silently throttle everything. `rate_limit_email_sent` is
        # per hour project-wide; `smtp_max_frequency` is a per-address cooldown
        # in seconds, which is what blocks a too-quick "Send a new code".
        "rate_limit_email_sent",
        "smtp_max_frequency",
    ]
    print("  current auth config:")
    for key in interesting:
        if key in config:
            print(f"    {key:26} = {config[key]!r}")
    for name in TEMPLATES:
        key = f"mailer_templates_{name}_content"
        body = config.get(key) or ""
        if not body:
            state = "empty (Supabase default = MAGIC LINK)"
        elif "{{ .Token }}" in body:
            state = "sends a code"
        elif ".ConfirmationURL" in body:
            state = "SENDS A LINK — will not work"
        else:
            state = "custom, no token found"
        print(f"    {name:26} -> {state}")


def check_smtp(gmail_address: str, gmail_password: str, send_to: str | None) -> None:
    """Log in to Gmail exactly as GoTrue will, and optionally send a test."""
    print(f"  connecting to {SMTP_HOST}:{SMTP_PORT} as {gmail_address} ...")
    context = ssl.create_default_context()
    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30) as server:
            server.starttls(context=context)
            server.login(gmail_address, gmail_password)
            print("  OK: STARTTLS + login succeeded, the App Password is valid.")
            if send_to:
                message = (
                    f"From: The Peptide Company <{gmail_address}>\r\n"
                    f"To: {send_to}\r\n"
                    "Subject: TPC SMTP test\r\n"
                    "\r\n"
                    "If you can read this, Supabase will be able to send your codes.\r\n"
                )
                server.sendmail(gmail_address, [send_to], message)
                print(f"  OK: test email sent to {send_to}.")
    except smtplib.SMTPAuthenticationError as error:
        raise SystemExit(
            "  FAILED: Gmail rejected the credentials.\n"
            "  Use a 16-character App Password (myaccount.google.com/apppasswords),\n"
            "  not your normal Gmail password. 2-Step Verification must be on.\n"
            f"  Gmail said: {error.smtp_error.decode(errors='replace')[:300]}"
        ) from error
    except (smtplib.SMTPException, OSError) as error:
        raise SystemExit(f"  FAILED: {error}") from error


def apply_config(token: str, ref: str, config: dict, dry_run: bool) -> None:
    before = get_auth_config(token, ref)
    summarise(before)

    unknown = [k for k in config if k not in before and k not in WRITE_ONLY_KEYS]
    if unknown:
        print(f"\n  note: not present in this project's config, sending anyway: {unknown}")

    if dry_run:
        redacted = {k: ("***" if k in WRITE_ONLY_KEYS else v) for k, v in config.items()}
        print("\n  --dry-run, would PATCH:")
        print(json.dumps(redacted, indent=2)[:2000])
        return

    print(f"\n  patching {len(config)} field(s) ...")
    patch_auth_config(token, ref, config)

    after = get_auth_config(token, ref)
    mismatched = [
        key
        for key, value in config.items()
        if key not in WRITE_ONLY_KEYS and str(after.get(key)) != str(value)
    ]
    print()
    summarise(after)
    if mismatched:
        raise SystemExit(f"\n  FAILED to take effect: {mismatched}")
    print("\n  OK: every field verified by reading the config back.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--show", action="store_true", help="print the current auth config")
    parser.add_argument("--check-smtp", action="store_true", help="verify the Gmail App Password")
    parser.add_argument("--apply", action="store_true", help="write SMTP + templates + Site URL")
    parser.add_argument("--dry-run", action="store_true", help="with --apply, print without writing")
    parser.add_argument("--send-test-to", metavar="EMAIL", help="with --check-smtp, send a test")
    args = parser.parse_args()

    if not (args.show or args.check_smtp or args.apply):
        parser.error("pick at least one of --show, --check-smtp, --apply")

    ref = os.environ.get("SUPABASE_PROJECT_REF", DEFAULT_PROJECT_REF)
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    gmail_address = os.environ.get("GMAIL_ADDRESS")
    # Google shows App Passwords as "abcd efgh ijkl mnop" for readability, but
    # the credential is the 16 characters without the spaces. Strip them here so
    # a copy-paste straight from the Google page works.
    raw_password = os.environ.get("GMAIL_APP_PASSWORD")
    gmail_password = "".join(raw_password.split()) if raw_password else None
    site_url = os.environ.get("TPC_SITE_URL")

    if gmail_password and len(gmail_password) != 16:
        print(
            f"  warning: App Password is {len(gmail_password)} characters, expected 16."
            " If your shell ate part of it, quote the value.",
            file=sys.stderr,
        )

    def require(value: str | None, name: str) -> str:
        if not value:
            raise SystemExit(f"{name} is not set. See the docstring at the top of this file.")
        return value

    if args.check_smtp:
        print("[check-smtp]")
        check_smtp(
            require(gmail_address, "GMAIL_ADDRESS"),
            require(gmail_password, "GMAIL_APP_PASSWORD"),
            args.send_test_to,
        )

    if args.show:
        print(f"\n[show] project {ref}")
        summarise(get_auth_config(require(token, "SUPABASE_ACCESS_TOKEN"), ref))

    if args.apply:
        print(f"\n[apply] project {ref}")
        apply_config(
            require(token, "SUPABASE_ACCESS_TOKEN"),
            ref,
            desired_config(
                require(gmail_address, "GMAIL_ADDRESS"),
                require(gmail_password, "GMAIL_APP_PASSWORD"),
                site_url,
            ),
            args.dry_run,
        )


if __name__ == "__main__":
    sys.exit(main())
