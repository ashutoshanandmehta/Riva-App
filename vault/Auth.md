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
