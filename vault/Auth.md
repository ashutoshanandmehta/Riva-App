# Auth

Identity and authentication run on **Supabase Auth** (GoTrue). Current state.

## How clients authenticate

- **iOS app — silent per-device account.** The app sends its stable
  `device_id` to `POST /v1/device/session`. The server (`backend.device_session`)
  derives a synthetic email `device-<sha256[:24]>@devices.riva.app` and a
  password = HMAC(service_role_key, "riva-device:<device_id>") — so only this
  server can compute it. It grants a password session via the GoTrue admin API,
  creating the account on first use, and returns `access_token`,
  `refresh_token`, `expires_at`, `user_id`, `email`. This is interim identity
  (no real sign-in screen yet). `device_id` must be 8–64 chars, alnum/dashes.
- **Web tester — email code.** `web/index.html` uses supabase-js email OTP
  sign-in against the public Supabase URL + anon key (served by `/v1/config`).
  Note: the public scanner path (`/v1/scan`) needs no auth at all.
- **iOS app — email + password.** The third provider on both the onboarding and
  login screens, alongside Google and Apple. See below.

## Email + password (iOS)

Entirely client-to-GoTrue: **no backend endpoint and no password storage of our
own.** GoTrue keeps a bcrypt hash in `auth.users.encrypted_password`, and that
is the only copy of the password that exists anywhere.

**Sign-up — code first, then password** (`AuthModel.EmailFlow.signUp`):

1. `POST auth/v1/otp` with `create_user: true` — emails a 6 digit code and
   creates the account on first use (`repository.requestCode`).
2. `POST auth/v1/verify` with `type: "email"` — returns a real session, so the
   address is now confirmed (`repository.verifyCode`).
3. `PUT auth/v1/user` with `{password}` on that bearer token
   (`repository.updatePassword`), then on to profile completion.

**Sign in:** `POST auth/v1/token?grant_type=password` (`repository.signIn`).

**Reset** (`EmailFlow.reset`) is the same three steps with the recovery grant:
`POST auth/v1/recover` → `POST auth/v1/verify` with `type: "recovery"` → the
same `PUT auth/v1/user`. Recovery deliberately reports success for addresses
that don't exist, so the screen can't be used to enumerate accounts.

Both journeys share one view (`Features/Auth/EmailFlowView.swift`) and one
three-step enum, since only the copy and the landing point differ.

**Password rules** live in `Core/Support/PasswordPolicy.swift` — on-device, no
network call. Per NIST SP 800-63B: 8–64 characters as the only composition
rule, plus a blocklist of common passwords checked against several
normalizations (leetspeak undone, leading/trailing padding stripped, both
orderings), keyboard walks, runs, low character variety, and the account's own
email fragments. Composition rules like "must contain a symbol" are
deliberately absent — they push people to `Password1!`, which the blocklist
catches and a symbol rule waves through.

**Email delivery is Supabase's, not ours.** Both codes are sent by GoTrue, so
the sender is configured in Supabase Dashboard → Project Settings →
Authentication → SMTP (Gmail: `smtp.gmail.com:587` + a Google App Password,
which needs 2FA on the account; the Sender email must equal the authenticated
Gmail account or Gmail rewrites it). Without custom SMTP configured, GoTrue's
shared sender is heavily rate-limited and the codes will not arrive reliably.
Gmail also caps around 500 sends/day, so a transactional provider is the
eventual move.

**The email templates must emit `{{ .Token }}`, not `{{ .ConfirmationURL }}`.**
This is the easiest thing to get wrong. Supabase ships every auth template as a
*magic link*, and a link is useless to this app twice over: the flow verifies a
typed code against `auth/v1/verify`, and the app registers **no URL scheme** in
`Info.plist` (the `riva-auth` scheme exists only as an
`ASWebAuthenticationSession` callback for Google, which needs no registration).
A link in the email therefore opens the Site URL in a browser — `localhost:3000`
if that was never changed — and can never reach the app.

Update all three templates under Dashboard → Authentication → Emails, because
`auth/v1/otp` picks a different one depending on whether the address already
exists:

| Template | Sent when |
|---|---|
| **Confirm signup** | `requestCode` for an address with no account yet |
| **Magic Link** | `requestCode` for an address that already has one |
| **Reset Password** | `requestPasswordReset` |

Also confirm Authentication → Email → **Email OTP Length is 6**, which is what
`AuthModel.codeLength` requires, and set a real **Site URL** under
Authentication → URL Configuration so no auth email ever points at localhost.

**Don't do any of that by hand.** `backend/scripts/configure_supabase_auth.py`
applies all of it through the Management API — SMTP, all three templates, OTP
length and expiry, Site URL — then verifies by reading the config back. Secrets
come from the environment (`SUPABASE_ACCESS_TOKEN`, `GMAIL_ADDRESS`,
`GMAIL_APP_PASSWORD`, `TPC_SITE_URL`); the script stores nothing. Stdlib only,
so there is no dependency to add.

    python backend/scripts/configure_supabase_auth.py --check-smtp   # validate the App Password
    python backend/scripts/configure_supabase_auth.py --show         # what's live now
    python backend/scripts/configure_supabase_auth.py --apply        # write + verify

Run `--check-smtp` first. GoTrue fails **silently** on bad SMTP credentials —
the send simply never happens and nothing surfaces in the app — so proving the
App Password separately is what turns a day of guessing into one clear error.

### Two throttles that look like a broken integration

- **`rate_limit_email_sent` — auth emails per hour, project-wide.** Supabase
  defaults it to **2** for its shared mailer and **does not raise it when you
  attach custom SMTP**. Left alone, the third signup of the hour fails with
  "email rate limit exceeded" no matter how much capacity Gmail has. The script
  sets it to 30 (Supabase's own custom-SMTP default, and clear of Gmail's
  ~500/day). This one bit us on 2026-07-28.
- **`smtp_max_frequency` — per-address cooldown, 60s.** Tapping "Send a new
  code" within a minute of the previous one fails with a *different* message
  ("you can only request this after N seconds"). That one is working as
  intended; don't confuse it with the limit above.

Both now appear in `--show`, which is how you tell the two apart.

## Server-side verification

`backend.verify_token()` calls `GET {SUPABASE_URL}/auth/v1/user` with the
caller's bearer token (and the anon apikey). A 200 yields the `user_id`;
anything else is a 401 ("Sign in to continue."). All authenticated endpoints go
through `_authenticate` / `_require_user` in `main.py`, which:
- return `None` / 503 in open stateless mode (no Supabase configured), and
- require `Authorization: Bearer <token>` otherwise.

The service-role key (`_service_headers`) is used only for admin/RPC calls,
never handed to clients. New `sb_secret_` keys go in the `apikey` header only;
legacy JWT (`eyJ…`) service_role keys also go in `Authorization`.

## iOS simulator token injection

OAuth can't complete in the simulator, so debug builds inject a session via
launch arguments read by `SupabaseAuthRepository`:

- `-riva.accessToken <AT>` and `-riva.refreshToken <RT>` — mint these with
  `POST /v1/device/session` (e.g. `{"device_id":"sim-demo-0001"}`), then:
  `xcrun simctl launch booted in.riva -riva.accessToken <AT> -riva.refreshToken <RT>`

Other debug launch args: `-riva.tab`, `-riva.snapMenuOpen`,
`-riva.scanTestImage`, `-riva.scanAutoAccept`, `-riva.auth`,
`-riva.accountSheet`, `-riva.detail`, `-riva.appearance`.

## Account lifecycle

`DELETE /v1/account` deletes the auth user via the GoTrue admin API
(`/auth/v1/admin/users/{id}`); all owned rows cascade-delete.
