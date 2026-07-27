# Privacy Policy — TPC (The Peptide Company)

**Effective date:** 27 July 2026
**Last updated:** 27 July 2026
**Applies to:** the TPC iOS app (bundle ID `in.riva`) and the TPC backend service

> **Fill these in before publishing** — App Review will follow the contact details:
> `[LEGAL ENTITY NAME]`, `[REGISTERED ADDRESS]`, `[GOVERNING LAW / JURISDICTION]`,
> `[PRIVACY CONTACT EMAIL]`. Every occurrence is bracketed in this document.

---

## 1. Who we are

TPC ("the app", "we", "us") is a wellness companion app for people using GLP-1
medication, published by `[LEGAL ENTITY NAME]` ("The Peptide Company"), registered at
`[REGISTERED ADDRESS]`.

This policy explains what the app collects, why, who else processes it, how long we keep
it, and how you can get a copy of it or delete it. It covers the iOS app and the backend
API that serves it.

**Contact for any privacy question or request:** `[PRIVACY CONTACT EMAIL]`

## 2. The short version

- We collect the account details you sign in with, the profile and health information you
  choose to log, and the photos you scan.
- **We do not sell your data, we do not share it for advertising, and we do not track you
  across other apps or websites.** The app contains no advertising SDK, no analytics SDK,
  and does not use the device advertising identifier (IDFA).
- Your data is stored in a per-user isolated account and is only reachable by your own
  signed-in session.
- Meal photos and your messages to the in-app AI companion are processed by Anthropic
  (Claude) to produce a result. Anthropic does not use them to train its models.
- You can **export everything** or **permanently delete your account and all data** from
  inside the app at any time: **Profile → Privacy**.

## 3. Important: this app is not medical advice

TPC is a wellness and self-tracking tool. It is **not a medical device**, it does not
diagnose or treat any condition, and nothing it shows — including nutrition estimates,
trends, reminders, or AI companion responses — is medical advice or a substitute for your
clinician or pharmacist. Never change a medication or dose based on this app. In an
emergency, contact your local emergency service.

We are not a healthcare provider, and we are not a HIPAA covered entity or business
associate. Information you enter here is **not** protected health information under HIPAA;
it is protected under this policy and applicable data protection law.

## 4. What we collect

We only collect what you give us or what the app needs to function. There is no background
collection, no location tracking, and no contact-list access.

### 4.1 Account and identity

| Data | Why | Source |
|---|---|---|
| Email address | Sign-in by one-time email code; account recovery | You |
| Apple ID name and email (Sign in with Apple) | Sign-in. If you choose **Hide My Email**, we only ever receive Apple's private relay address | Apple |
| Account identifier (UUID), sign-in timestamps, session tokens | Authenticating you and keeping you signed in | Generated |

### 4.2 Profile

Name, date of birth, gender (optional, including "prefer not to say"), height, starting
weight, goal weight, your clinician's name (optional, if you choose to record it), and
time zone.

Date of birth is used to age-gate the app and to contextualise your goals. Time zone is
used so reminders and daily totals land on the correct day.

### 4.3 Health and wellness data you log

This is **sensitive / special-category** data, and we treat it as such:

- **Weight** entries over time
- **Medication plan and injections** — the GLP-1 medication you record, dose, and the dates
  you log a shot
- **Side effects** you report, and their severity
- **Check-in answers** about how you are feeling
- **Nutrition** — foods and drinks logged, water intake, per-day totals, and your protein,
  carbohydrate, fibre and water goals
- **Health goals** — for example GLP-1 support, weight management, muscle preservation,
  exercise, sleep and recovery
- **Wellness sessions** you complete
- **Reminders / to-dos** you create, including any text you type into them
- **AI companion conversations** — your messages, the assistant's replies, and the
  structured results behind an answer

### 4.4 Photos and camera

When you scan a meal, drink, or water, the app captures image frames and sends them to our
backend for analysis. The camera is used **only** while you are actively scanning.

**We do not store your photos.** Images are transmitted over an encrypted connection, used
to produce the nutrition estimate, and discarded once the result is returned. They are not
written to our database and are not retained after the scan completes.

### 4.5 Technical and diagnostic data

Our backend and hosting provider record standard server logs — IP address, timestamp,
requested endpoint, response status and timing, and error diagnostics. These are used to
operate and secure the service and to debug faults. They are not used to profile you or
build an advertising audience.

### 4.6 Notifications

Reminders are scheduled **locally on your device** by iOS. We do not operate a push
notification service for reminders and we do not collect a push token for them. You can
revoke notification permission at any time in iOS Settings.

## 5. How we use your data, and our legal basis

| Purpose | Legal basis (UK/EU GDPR) |
|---|---|
| Create and authenticate your account | Performance of a contract (Art. 6(1)(b)) |
| Store and display the health, nutrition and wellness data you log | Your **explicit consent** for special-category data (Art. 9(2)(a)); contract for the service itself |
| Analyse a meal photo to estimate nutrition | Contract; explicit consent for health data |
| Provide AI companion answers using your logged context | Contract; explicit consent for health data |
| Send reminders you have set up | Contract; your device-level notification consent |
| Keep the service secure, prevent abuse, debug faults | Legitimate interests (Art. 6(1)(f)) |
| Comply with legal obligations | Legal obligation (Art. 6(1)(c)) |

You can withdraw consent at any time by deleting the relevant entries, or by deleting your
account (section 8), which removes the data entirely.

We do **not** use your data for automated decision-making that has a legal or similarly
significant effect on you. The AI companion produces informational content only.

## 6. AI processing

Two features send your content to **Anthropic PBC** for processing by its Claude models:

1. **Meal scanning** — the photo you scan, to identify the food and estimate nutrition.
2. **AI companion chat** — your messages, plus relevant context from the data you have
   logged (for example recent weight or nutrition entries) so the answer is useful.

Anthropic processes this content as our service provider, under its commercial API terms.
**Your content is not used to train Anthropic's models.** Anthropic retains it only
transiently for abuse monitoring, then deletes it.

Your chat conversations are stored in your own account so you can read them again later.
Deleting your account deletes them.

## 7. Who else processes your data

We use a small number of service providers ("processors"). We do not sell your data to
anyone, and none of these providers may use it for their own purposes.

| Provider | What it handles | Where |
|---|---|---|
| **Supabase** | Authentication and the database holding your profile, health, nutrition, wellness and chat data | United States |
| **Render** | Hosting for our backend API; server logs | United States |
| **Anthropic** | Meal photo analysis and AI companion responses (section 6) | United States |
| **USDA FoodData Central** | Public nutrition reference lookups. We send **food search terms only** — never your identity, account, or health data | United States |
| **Apple** | Sign in with Apple, App Store and TestFlight distribution, on-device notification scheduling | Per Apple's policy |
| **YouTube (Google)** | Some wellness content is an embedded YouTube video. If you play one, YouTube receives your IP address and device information and may set cookies, under **Google's** privacy policy, not ours | Google infrastructure |

We may also disclose data if legally required (for example a valid court order), to protect
someone's safety or our legal rights, or to a successor in the event of a merger or
acquisition — in which case this policy continues to apply, or you will be notified before
any change.

## 8. Your rights and controls

**In the app, right now — Profile → Privacy:**

- **Export my data** — produces a complete machine-readable JSON copy of your account,
  which you can save or share.
- **Delete my data** — permanently deletes your account and every record attached to it
  (profile, weights, shots, side effects, check-ins, nutrition entries, wellness sessions,
  to-dos and chat history). This is immediate and irreversible; there is no recovery.

Depending on where you live, you also have the right to access, correct, delete, restrict
or object to processing of your data, to data portability, to withdraw consent, and to lodge
a complaint with a supervisory authority. To exercise any right, email
`[PRIVACY CONTACT EMAIL]`. We respond within 30 days (or one month in the UK/EEA), and we
will not discriminate against you for exercising a right.

### EEA and UK

Your data is transferred to and processed in the United States. Where required, these
transfers rely on the European Commission's **Standard Contractual Clauses** (and the UK
International Data Transfer Addendum) with each processor. You may complain to your local
supervisory authority, or the UK Information Commissioner's Office.
`[EU/UK REPRESENTATIVE, IF REQUIRED]`

### California

We do not sell personal information and we do not share it for cross-context behavioural
advertising. We collect the categories described in section 4, including **sensitive
personal information** (health data), which we use only to provide the service you asked
for — never to infer characteristics for advertising. You have the rights to know, delete,
correct, and limit the use of sensitive personal information; the in-app controls above
satisfy the access and deletion rights immediately.

### Other US states

Residents of states with comprehensive privacy laws (including Colorado, Connecticut,
Virginia, Utah and Texas) have equivalent rights of access, correction, deletion and
portability, and may appeal a refused request by writing to `[PRIVACY CONTACT EMAIL]`.

## 9. How long we keep data

- **Account, profile, health, nutrition, wellness and chat data** — until you delete the
  entry or your account. We do not impose our own expiry, because the app's value is the
  history.
- **Meal photos** — not retained; discarded once the scan result is returned.
- **Server logs** — retained for a short operational period for security and debugging,
  then rotated out.
- **Backups** — deleted data may persist briefly in encrypted backups before those expire.

## 10. Security

- All traffic between the app, our backend, and our processors uses **TLS**.
- The database enforces **row-level security**: every query is scoped to the signed-in
  user, so one account cannot read another's data.
- Privileged writes happen server-side with credentials that are never present in the app.
- Access to production systems is limited to personnel who need it.

No system is perfectly secure. If a breach affects your data, we will notify you and the
relevant regulator as required by law.

## 11. Children

TPC is intended for adults aged **18 and over**, because it is a companion for prescription
GLP-1 medication. We do not knowingly collect data from children. If you believe a child has
created an account, email `[PRIVACY CONTACT EMAIL]` and we will delete it.

## 12. Changes to this policy

If we change how we handle your data we will update this page and the "Last updated" date.
For material changes — a new category of data, a new processor, or a new purpose — we will
notify you in the app before the change takes effect, and where the law requires it, ask for
your consent again.

## 13. Contact

`[LEGAL ENTITY NAME]`
`[REGISTERED ADDRESS]`
**Privacy enquiries and rights requests:** `[PRIVACY CONTACT EMAIL]`

This policy is governed by the laws of `[GOVERNING LAW / JURISDICTION]`.
