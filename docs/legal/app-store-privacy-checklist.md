# App Store / TestFlight privacy submission checklist

Companion to `privacy-policy.md`. The policy alone does not get you through review — the
**App Privacy answers in App Store Connect must match it**, and a mismatch is one of the
most common rejections. Work top to bottom.

## 1. Host the policy at a public URL

App Store Connect requires a URL that loads **without a login** and is not a redirect to a
generic homepage. `privacy-policy.html` is self-contained (no assets, no JS) and can be
served as-is.

- **Easiest:** commit `docs/legal/privacy-policy.html`, enable GitHub Pages on the repo, and
  use `https://<user>.github.io/<repo>/legal/privacy-policy.html`.
- **Alternative:** serve it as a static route from the existing Render service. Note that
  Render auto-deploy is OFF and deploys are a gated operation — do not push without approval.

Then paste the URL in **two** places:

| Where | Field |
|---|---|
| App Store Connect → your app → **App Information** | Privacy Policy URL |
| App Store Connect → **TestFlight → Test Information** | Privacy Policy URL (required for **external** testers; internal-only testing does not check it) |

## 2. App Privacy answers ("nutrition label")

App Store Connect → your app → **App Privacy → Data Types**. Declare exactly these.

For **every** row below: **Linked to the user = Yes**, **Used for tracking = No**.

| Apple data type | What it is in this app | Purposes |
|---|---|---|
| Contact Info → **Name** | Profile name; Apple ID full name | App Functionality |
| Contact Info → **Email Address** | Email-code sign-in; Apple relay address | App Functionality |
| Health & Fitness → **Health** | Weight, medication plan and shots, side effects, check-ins, nutrition | App Functionality, Product Personalization |
| Health & Fitness → **Fitness** | Wellness sessions, movement/exercise goals | App Functionality, Product Personalization |
| User Content → **Photos or Videos** | Meal/drink scan frames sent for analysis | App Functionality |
| User Content → **Other User Content** | AI companion messages, to-do text, side-effect notes | App Functionality, Product Personalization |
| Identifiers → **User ID** | Account UUID | App Functionality |
| **Other Data Types** | Date of birth, gender, height, time zone, clinician name | App Functionality |

**Do not declare:** Location, Contacts, Browsing/Search History, Purchases, Advertising Data,
Device ID, Crash/Performance Data. None are collected — there is no analytics or advertising
SDK and no IDFA use.

Answer **No** to "Do you or your third-party partners use data for tracking purposes?" This
means **no `NSUserTrackingUsageDescription` and no ATT prompt** — do not add one, or review
will ask why it appears.

> Photos are declared even though they are discarded after the scan, because they leave the
> device. Declaring is the safe reading of Apple's rule; the policy explains the no-retention
> part.

## 3. Account deletion — Guideline 5.1.1(v)

The app supports account creation, so Apple **requires** in-app account deletion. This exists:
**Profile → Privacy → Delete my data**, which calls `DELETE /v1/account` and deletes the auth
user (all rows cascade).

In the review notes, spell out the path verbatim so the reviewer can find it:

> Account deletion: Profile tab → Privacy → "Delete my data" → confirm. This permanently
> deletes the account and all associated records.

## 4. Sign-in for the reviewer — Guideline 2.1

Sign-in is by **one-time code sent to an email address**, which App Review cannot receive.
Do not leave this to chance:

- **Sign in with Apple is enabled**, so the reviewer can sign in with their own Apple ID.
  State this explicitly in App Review Information.
- **Also** provide a demo account whose inbox you can monitor, or a fixed test address, in the
  **App Review Information → Sign-In Required** fields.

Suggested review note:

> Sign in with Apple is supported — please use it, or the demo credentials provided. Email
> sign-in uses a one-time code, so the demo account is the reliable path.

## 5. Age rating

Set the rating from the questionnaire with **Medical/Treatment Information** declared. This is
a companion for prescription GLP-1 medication, so the policy states **18+**. Keep the App
Store age rating consistent with that — a 4+ rating alongside a policy that says "adults aged
18 and over" is a contradiction a reviewer can act on.

## 6. Privacy manifest — add the file to the target

`ios/Riva/PrivacyInfo.xcprivacy` has been created but is **not yet in the Xcode project**. The
app uses `UserDefaults`, a required-reason API; without the manifest, uploads get an
**ITMS-91053 "Missing API declaration"** email from Apple.

In Xcode (project is already open):

1. Drag `PrivacyInfo.xcprivacy` into the project navigator under the `Riva` group.
2. Check **Copy items if needed = off**, and tick the app target.
3. Confirm it lands in **Target → Build Phases → Copy Bundle Resources**.

Keep it in sync with section 2 — the manifest, the label, and the policy are three copies of
the same claims.

## 7. Verify these three claims are actually true in production

Each is asserted in the policy. If any is false at deploy time, the policy is inaccurate.

- **`RIVA_VOLUMETRIC_CAPTURE_DIR` must be unset on Render.** Setting it makes
  `capture_store.py` bank every uploaded scan frame to disk, which contradicts "we do not
  store your photos." It is off by default.
- **`REPLICATE_API_TOKEN` and `SAM2_ENDPOINT_URL` must be unset on Render** — otherwise scan
  images are sent to Replicate or a self-hosted SAM 2 endpoint, neither of which is listed in
  the processor table. If either is enabled, add it to section 7 of the policy.
- **`/v2/scan` must stay unused.** It proxies photos to `caloriemama.ai`, a third party the
  policy does not list. The iOS app only calls `/v1/scan` and `/v1/scan/volumetric`, so it is
  currently excluded — correctly. (Separately, that endpoint sends a spoofed
  `Referer`/`Origin` to impersonate CalorieMama's own web demo. That is a terms-of-service
  problem independent of privacy, and it should not ship enabled.)

## 8. Before publishing, fill in the placeholders

Both `privacy-policy.md` and `privacy-policy.html` contain bracketed fields. Reviewers do read
the contact section, and an unfilled `[LEGAL ENTITY NAME]` looks unfinished:

- `[LEGAL ENTITY NAME]` — the registered company that publishes the app
- `[REGISTERED ADDRESS]` — a real postal address
- `[PRIVACY CONTACT EMAIL]` — a monitored address; a `privacy@` alias is better than a
  developer inbox
- `[GOVERNING LAW / JURISDICTION]`
- `[EU/UK REPRESENTATIVE, IF REQUIRED]` — needed only if you target the EEA/UK without an
  establishment there; delete the line otherwise

## 9. Not covered here

- **Terms of Service** — not required for a free app with no subscription, but expected
  alongside a health app. Worth writing before public launch.
- **Legal review.** This policy was drafted from what the code actually does, which is the
  part software can verify. Whether it satisfies your obligations in each market you ship to
  is a question for a lawyer, particularly because it involves special-category health data.
