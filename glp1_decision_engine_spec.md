# GLP-1 Companion Application — Decision Engine Specification

**Document Type:** Clinical Decision Support System (CDSS) Protocol Manual
**Applies To:** Companion applications supporting GLP-1 / GIP-GLP-1 receptor agonist therapy (e.g., semaglutide products such as Wegovy/Ozempic, tirzepatide products such as Zepbound/Mounjaro)
**Audience:** Backend engineers, clinical safety reviewers, AI/prompt engineers, QA, compliance
**Document Status:** Draft v1.0 — For implementation review
**Classification:** This document specifies a *deterministic decision engine*. It is not a prompt. It is not medical software validated as a Software as a Medical Device (SaMD) unless separately cleared; treat all thresholds herein as configurable clinical parameters requiring sign-off from a licensed clinical lead (e.g., obesity medicine physician, endocrinologist, or NP/PA with prescribing scope) before production release.

---

## 0. How to Read This Document

The application pipeline is:

```
User Message
   -> 0. Safety Pre-Filter (crisis / emergency keyword scan)
   -> 1. Intent Classification
   -> 2. Risk Classification
   -> 3. Patient Context Retrieval
   -> 4. Missing Information Collection
   -> 5. Decision Engine (deterministic rule evaluation)
   -> 6. Personalization Layer
   -> 7. AI Composer (natural-language generation, constrained to engine output)
   -> 8. Memory Update
   -> 9. Follow-up Scheduler
```

The **Decision Engine** (steps 1-6, 9) is deterministic, versioned, and independently testable. The **AI Composer** (step 7) is a bounded natural-language generator: it may only rephrase, explain, and empathetically frame the structured output the Decision Engine hands it. It may never introduce a recommendation, dosage, or clinical claim that did not originate from the engine. This separation is the core architectural invariant of the system and is referenced throughout this document as the **Protocol/Composer Boundary**.

---

## 1. Guiding Principles

These principles are non-negotiable constraints on every component of the system, including the AI Composer. They are enforced in code (Section 12), not just documentation.

| # | Principle | Operational Meaning |
|---|---|---|
| P1 | **Safety first** | When any rule conflicts with user satisfaction or engagement metrics, safety wins. No dark patterns that discourage escalation. |
| P2 | **Never diagnose** | The engine outputs *risk levels* and *educational content*, never a named diagnosis (e.g., never "you have gastroparesis"; instead "this pattern of symptoms is one your prescriber should evaluate"). |
| P3 | **Never prescribe or alter medication** | The engine never tells a user to start, stop, skip, split, or change a dose beyond what is explicitly printed in the FDA-approved Instructions for Use / Medication Guide for missed-dose timing. All other dose changes route to the prescriber. |
| P4 | **Never replace clinician judgment** | Every output includes an explicit statement that the tool is educational/supportive and does not substitute for the prescribing clinician. |
| P5 | **Evidence-based only** | Every decision rule cites a source (FDA label, peer-reviewed guideline, or professional society position statement) in its rule metadata (Section 15). |
| P6 | **Escalate uncertainty** | If confidence in intent or risk classification falls below threshold, or required information cannot be collected, default to the more conservative (higher-risk) path. |
| P7 | **Deterministic behavior** | Same inputs (message + patient context + protocol version) always produce the same risk level and rule outcome. AI Composer variability is confined to phrasing, never to substance. |
| P8 | **Explainable decisions** | Every engine output carries a machine-readable trace of which rule(s) fired and why (Section 7.4). |
| P9 | **Version-controlled protocols** | Every rule set has an ID, semantic version, effective date, and owner (Section 15). |
| P10 | **Auditability** | Every user-facing response is reconstructable from logs: intent, risk, rules fired, patient context snapshot used, composer output, and timestamps (Section 12). |
| P11 | **Least-privilege personalization** | Personalization may reference the user's own logged data only; it may never infer or state clinical conclusions not licensed by a fired rule. |
| P12 | **Fail closed, not open** | Any system error (context fetch failure, classifier timeout, ambiguous input) routes to a safe, generic, escalation-leaning fallback response rather than a best-guess clinical answer. |

---

## 2. Intent Taxonomy & Classification

### 2.1 Design Rule

Every incoming message is classified into **exactly one Primary Intent** from the closed taxonomy below, plus zero or more **Secondary Intents** (see 2.4, Multi-Intent Handling). Classification never leaves an intent unresolved; if no category matches with sufficient confidence, the message is routed to `OTHER` and, if risk signals are present, elevated per Section 3.

### 2.2 Intent Taxonomy

| Domain | Intent ID | Intent Name |
|---|---|---|
| Medication | `MED.DOSE` | Dose Questions |
| Medication | `MED.MISSED` | Missed Dose |
| Medication | `MED.INJ_TECHNIQUE` | Injection Technique |
| Medication | `MED.INJ_SITE` | Injection Site Issues |
| Medication | `MED.INJ_TIMING` | Injection Timing |
| Medication | `MED.STORAGE` | Medication Storage |
| Medication | `MED.TRAVEL` | Travel (medication logistics) |
| Medication | `MED.INTERACTIONS` | Medication Interactions |
| Medication | `MED.INSURANCE` | Insurance / Prescription Navigation |
| Lifestyle | `LIFE.NUTRITION` | Nutrition (general) |
| Lifestyle | `LIFE.PROTEIN` | Protein Intake |
| Lifestyle | `LIFE.HYDRATION` | Hydration |
| Lifestyle | `LIFE.EXERCISE` | Exercise |
| Lifestyle | `LIFE.SLEEP` | Sleep |
| Lifestyle | `LIFE.COACHING` | General Lifestyle Coaching |
| Progress | `PROG.WEIGHT_TRACK` | Weight Tracking |
| Progress | `PROG.PLATEAU` | Weight Plateau |
| Progress | `PROG.INTERPRET` | Progress Interpretation |
| Side Effect | `SE.NAUSEA` | Nausea |
| Side Effect | `SE.VOMITING` | Vomiting |
| Side Effect | `SE.CONSTIPATION` | Constipation |
| Side Effect | `SE.DIARRHEA` | Diarrhea |
| Side Effect | `SE.HEARTBURN` | Heartburn / Reflux |
| Side Effect | `SE.FATIGUE` | Fatigue |
| Side Effect | `SE.DIZZINESS` | Dizziness |
| Side Effect | `SE.HEADACHE` | Headache |
| Side Effect | `SE.APPETITE` | Appetite Changes |
| Psychological | `PSY.EMOTIONAL_EAT` | Emotional Eating |
| Psychological | `PSY.WELLBEING` | Mental Wellbeing |
| Clinical | `CLIN.LABS` | Lab Questions |
| Clinical | `CLIN.EDUCATION` | General Education |
| Clinical | `CLIN.PREGNANCY` | Pregnancy Questions |
| Clinical | `CLIN.EMERGENCY` | Emergency Symptoms |
| Other | `OTHER` | Uncategorized / Out of Scope |

### 2.3 Classification Method

1. **Pre-filter pass (Section 3.5):** message scanned against the RED-flag lexicon and pattern set before intent classification runs, so an emergency is never delayed behind intent disambiguation.
2. **Primary classifier:** an intent classification model (or ensemble of a lightweight embedding classifier + LLM verifier) scores the message against all taxonomy entries and returns a ranked list with confidence scores.
3. **Decision:** the top-ranked intent is accepted as Primary Intent only if `confidence >= 0.72` (tunable per Section 15). Below threshold, the system asks one deterministic disambiguation question drawn from a pre-written bank (never freeform), e.g., "Is this about how the medication is dosed, or a side effect you're feeling?"
4. **Ties:** if two intents score within 0.05 of each other, the higher-risk-tier intent (per Section 3) is selected by default, and the lower one is retained as a Secondary Intent.

### 2.4 Multi-Intent Handling

A single message may contain multiple intents (e.g., "I'm nauseous and also want to know if I can drink alcohol on this"). The engine:
- Classifies all intents present, not only the first mentioned.
- Processes them by descending risk tier — highest-risk protocol runs first, completely, before lower-risk protocols are addressed in the same response or a follow-up turn.
- Never silently drops a stated intent; if only the top intent is answered in this turn, the response explicitly acknowledges the deferred item(s).

### 2.5 Example Classifications

| Message | Primary Intent | Notes |
|---|---|---|
| "I forgot to take my shot yesterday, what do I do?" | `MED.MISSED` | Deterministic timing table applies (Section 5.1). |
| "I've thrown up three times today and can't keep water down" | `SE.VOMITING` (auto-escalates toward RED, see 5.5) | Dehydration risk pattern. |
| "Why has my weight not moved in 3 weeks?" | `PROG.PLATEAU` | |
| "Can I take ibuprofen with Zepbound?" | `MED.INTERACTIONS` | |
| "I just feel really down lately, is that normal on this med?" | `PSY.WELLBEING` | Screened per Section 5.20; not assumed to be medication side effect without context. |
| "chest pain and can't catch my breath" | `CLIN.EMERGENCY` | Bypasses normal classification via Section 3.5 pre-filter. |
| "what's the weather" | `OTHER` | Out of scope; polite redirect, no clinical protocol invoked. |

---

## 3. Risk Classification Protocol

### 3.1 Purpose

Every message — regardless of intent — receives a risk tier of **RED**, **YELLOW**, or **GREEN**. Risk classification is computed *after* the pre-filter (3.5) and *alongside* intent classification, and it gates which decision rules and response templates are permitted to fire (P6, P12).

### 3.2 GREEN — Routine / Educational

**Definition:** No signal of acute medical risk. General questions about lifestyle, medication logistics, or mild, expected, self-limited symptoms with no red/yellow modifiers present.

**Examples:** "How much protein should I eat?", "Best time of day to inject?", "Can I still enjoy pizza sometimes?", mild first-week nausea with no vomiting, normal hydration, no other symptoms.

**Required Actions:** Standard protocol execution; personalization; standard educational content.

**Allowed Responses:** Full educational and coaching content, self-care guidance, monitoring instructions.

**Escalation Path:** None required. Standard "contact your care team if this worsens" boilerplate included.

**Documentation Requirements:** Log intent, risk tier, rules fired.

**Follow-up Requirements:** Per protocol-specific cadence (Section 5), typically none-to-light-touch.

### 3.3 YELLOW — Monitor / Clinician Awareness Recommended

**Definition:** Symptom or question with a plausible but not immediately dangerous clinical significance; a known, labeled side effect that is more than mild, is persistent, or combines with a mild modifier (e.g., diarrhea for 3 days without dehydration signs; moderate injection-site reaction; missed dose beyond the labeled window; questions suggesting a plateau plus signs of disordered eating).

**Required Actions:** Run applicable decision rules; deliver conservative, non-alarming guidance; explicitly recommend contacting the prescriber's office within a defined window (typically 24-72h, protocol-specific); schedule a structured follow-up check-in.

**Allowed Responses:** Self-care measures explicitly listed in decision rules only; clear statement of what would upgrade the situation to RED; explicit "contact your care team" instruction with suggested timeframe.

**Escalation Path:** If a scheduled follow-up shows worsening, no improvement after the expected timeline, or a new RED modifier appears, escalate to RED.

**Documentation Requirements:** Log full symptom detail, rule trace, and instructions given; flag record for possible care-team visibility if the app has a provider-facing dashboard.

**Follow-up Requirements:** Mandatory. Timing defined per protocol (Section 5); non-response to a YELLOW follow-up after 2 attempts triggers a passive escalation prompt.

### 3.4 RED — Urgent / Emergency

**Definition:** Any pattern matching a known serious adverse event associated with GLP-1/GIP-GLP-1 therapy, or any generally life-threatening symptom regardless of medication relevance. This includes but is not limited to: signs of acute pancreatitis (severe, persistent abdominal pain radiating to the back, often with vomiting); signs of gallbladder/biliary obstruction (right upper quadrant pain, fever, jaundice); signs of dehydration/acute kidney injury following GI losses (dark urine, minimal urination, dizziness/fainting, confusion, inability to keep any fluids down for 24h); signs of severe hypersensitivity (facial/throat swelling, difficulty breathing, hives with dizziness); signs of hypoglycemia with altered mental status (in patients on insulin/sulfonylureas); suicidal ideation or self-harm intent; chest pain, difficulty breathing, stroke symptoms; suspected bowel obstruction (severe bloating, no bowel movements/gas, vomiting); pregnancy with concurrent GLP-1 use.

**Required Actions:** Immediately halt normal protocol flow. Do not attempt further information-gathering beyond what is necessary to route correctly (e.g., "are you safe right now," "can you call 911 or have someone call for you"). Surface emergency guidance without delay.

**Allowed Responses:** Only pre-approved emergency-routing language: instruct the user to contact emergency services (911 in the U.S., or local equivalent) or go to an emergency department now; for mental health crises, provide crisis resources (e.g., 988 Suicide & Crisis Lifeline in the U.S.) in addition to, not instead of, general emergency guidance. No self-care suggestions. No "try this first."

**Escalation Path:** Terminal — outside the app's authority. If the app has a live clinical escalation channel (nurse triage line, care team paging), invoke it in parallel with the user-facing message.

**Documentation Requirements:** Full transcript, timestamp, risk trace, and (if available) automatic provider notification logged as a high-priority audit event.

**Follow-up Requirements:** A wellness-check follow-up is scheduled for a short interval after a RED event (e.g., 2-4 hours if the user remains in-app, next business day otherwise) to confirm the user received care, without requesting clinical detail that could delay action in the moment.

### 3.5 Emergency Pre-Filter (Runs Before Everything Else)

A deterministic lexicon/pattern scan (regex + curated phrase list, not solely model-based, to guarantee recall) runs on every inbound message before intent classification. Matches include direct emergency language ("can't breathe," "chest pain," "throwing up blood," "haven't peed all day," "thinking about ending my life," "swelling in my throat"). Any match short-circuits the pipeline directly to the RED protocol (Section 3.4) and `CLIN.EMERGENCY` intent, bypassing normal intent/risk scoring. This filter is intentionally high-recall/low-precision — false positives (an over-triggered RED) are an acceptable cost; false negatives are not.

---

## 4. Patient Context Schema

The engine automatically retrieves context before evaluating rules; it never re-asks the user for information already known and current. All fields are versioned and timestamped so the engine can assess *staleness* (e.g., a weight entry from 40 days ago is not "current").

| Field | Type | Source | Staleness Rule |
|---|---|---|---|
| `medication.name` | enum (semaglutide/tirzepatide/other) | Onboarding / provider import | Re-confirm every 90 days |
| `medication.brand` | string | Onboarding | — |
| `medication.current_dose_mg` | float | Onboarding + dose-change events | Re-confirm on any dose-question intent |
| `medication.treatment_week` | int | Computed from start date | Always fresh (derived) |
| `medication.last_injection_date` | date | User log | Used for `MED.MISSED` logic |
| `medication.adherence_pattern` | derived (on-time/delayed/erratic) | Computed from injection log | Rolling 8-week window |
| `weight.trend` | derived series | User-logged weigh-ins | Flag if no entry in 14 days |
| `weight.bmi` | float | Height + latest weight | Recomputed each new weight entry |
| `nutrition.food_log_summary` | derived | Optional food logging feature | Only used if user opts in |
| `hydration.avg_daily_l` | float | Optional hydration logging | Only used if user opts in |
| `activity.summary` | derived | Optional activity logging / wearable integration | Only used if user opts in |
| `injection.history` | list | User log (site, date, technique flags) | Rolling 12 weeks |
| `symptoms.history` | list | Prior symptom reports + resolution status | Full history, risk-relevant entries never purged |
| `contraindications.known` | list | Onboarding intake + provider import | Re-confirmed at each major dose change |
| `recommendations.previous` | list | Engine output log | Full history |
| `conversation.recent_summary` | derived | Last N structured memory entries (Section 8), **not raw chat log** | Rolling 30 days |
| `labs.latest` | structured (if available) | Provider/EHR integration (optional) | Flag if > 6 months old |
| `provider.instructions` | structured | Provider portal / care-team notes (optional integration) | Always takes precedence over generic protocol defaults where present |
| `demographics.pregnancy_status` | enum (not pregnant / pregnant / trying to conceive / unknown) | Onboarding + explicit updates | Re-confirmed on any `CLIN.PREGNANCY` or missed-period mention |
| `demographics.age` | int | Onboarding | — |

**Rule:** if `provider.instructions` conflicts with a default protocol recommendation (e.g., provider has instructed a different missed-dose approach), the provider instruction wins and is used verbatim in the personalization layer, with the generic protocol demoted to background context only (P4).

---

## 5. Intent Protocols

Each protocol below follows a fixed template: **Goal**, **Required Inputs** (must come from the user's message), **Required Patient Context** (auto-retrieved, Section 4), **Default Risk Level** (may be upgraded by modifiers), **Missing-Information Questions** (asked only if not already known/current), **Decision Rules** (deterministic IF/THEN), **Escalation Conditions**, **Follow-up Logic**. Decision rules use the format:

```
RULE <intent>.<n>
IF <condition(s)>
THEN
  RECOMMEND: <protocol-level recommendation text — generic, not personalized>
  FOLLOW_UP: <if any>
  ESCALATE: <if any>
  LOG: <structured fields written to memory>
  SOURCE: <evidence citation>
```

### 5.1 `MED.DOSE` — Dose Questions

**Goal:** Answer questions about current/next dose, titration schedule, or dose-related concerns without ever recommending a dose change.

**Required Inputs:** Nature of the question (what is my dose / when does it increase / can I increase early / can I decrease).

**Required Patient Context:** `medication.name`, `medication.current_dose_mg`, `medication.treatment_week`, `provider.instructions`.

**Default Risk Level:** GREEN. Upgrades to YELLOW if the user expresses intent to self-adjust dose against protocol (e.g., wants to increase faster than labeled titration) or reports intolerable side effects at current dose.

**Missing-Information Questions:** None beyond context if context is current; if `medication.current_dose_mg` is stale/unknown, ask directly.

**Decision Rules:**
```
RULE MED.DOSE.1
IF user asks "what is my current dose"
THEN
  RECOMMEND: State current_dose_mg and treatment_week from context.
  LOG: intent, no clinical content change.
  SOURCE: n/a (informational retrieval)

RULE MED.DOSE.2
IF user asks about upcoming titration step
THEN
  RECOMMEND: State the labeled titration schedule for medication.name (starting/maintenance steps, minimum interval between increases per FDA label) and where current_dose_mg sits on that schedule.
  SOURCE: FDA-approved Prescribing Information / Medication Guide for the specific product.

RULE MED.DOSE.3
IF user expresses desire to increase dose faster than the labeled minimum interval (e.g., "can I just jump to the next dose early")
THEN
  RECOMMEND: Explain labeled minimum titration interval exists to reduce GI side-effect risk; state this is a decision for the prescriber, not a self-directed change.
  ESCALATE: YELLOW — route to "contact prescriber before changing dose."
  LOG: self-titration intent flag = true (relevant for adherence/safety monitoring).

RULE MED.DOSE.4
IF user reports side effects are intolerable at current dose and asks whether to lower it themselves
THEN
  RECOMMEND: Do not instruct a self-directed dose decrease; explain that dose adjustments (including staying at a lower step longer) are made with the prescriber; offer to help document symptoms for that conversation.
  ESCALATE: YELLOW.
  FOLLOW_UP: 48-72h check whether prescriber was contacted.
```

**Escalation Conditions:** Any stated intent to self-adjust dose outside labeled parameters; reports of taking more than one dose in the same week.

**Follow-up Logic:** None for informational GREEN queries; 48-72h check-in for YELLOW self-titration-intent cases.

---

### 5.2 `MED.MISSED` — Missed Dose

**Goal:** Apply the FDA-labeled missed-dose window deterministically; never improvise timing.

**Required Inputs:** Time elapsed since the missed scheduled dose (in days/hours).

**Required Patient Context:** `medication.name`, `medication.last_injection_date`.

**Default Risk Level:** GREEN, unless the user has missed multiple consecutive doses (possible loss of tolerance) which upgrades to YELLOW.

**Missing-Information Questions:** "How many days has it been since your scheduled dose?" if not derivable from `last_injection_date`.

**Decision Rules:**
```
RULE MED.MISSED.1
IF medication.name is tirzepatide-based (Zepbound/Mounjaro) AND days_since_missed < 4
THEN
  RECOMMEND: Take the missed dose as soon as possible, then resume the regular weekly schedule; do not take two doses within 3 days of each other.
  SOURCE: Zepbound (tirzepatide) FDA Medication Guide / Prescribing Information — missed dose section.

RULE MED.MISSED.2
IF medication.name is tirzepatide-based AND days_since_missed >= 4
THEN
  RECOMMEND: Skip the missed dose; take the next dose on the regular scheduled day. Do not double up.
  SOURCE: Zepbound (tirzepatide) FDA Medication Guide.

RULE MED.MISSED.3
IF medication.name is semaglutide-based (Wegovy/Ozempic) AND days_since_missed <= 5 (<= 5 days / within the product's specific labeled window)
THEN
  RECOMMEND: Take the missed dose as soon as possible per the product's specific Medication Guide window; then resume regular schedule.
  SOURCE: Product-specific FDA Medication Guide (verify exact day threshold per brand at rule-config time — semaglutide products' labeled windows differ slightly by brand/formulation and must be sourced from the current label, not assumed).

RULE MED.MISSED.4
IF days_since_missed exceeds the product's labeled window
THEN
  RECOMMEND: Skip the missed dose; resume on the next regularly scheduled day; do not double up to "catch up."
  SOURCE: Product-specific FDA Medication Guide.

RULE MED.MISSED.5
IF user has missed >= 2 consecutive scheduled doses (>= 2 weeks with no injection)
THEN
  RECOMMEND: Advise contacting the prescriber before resuming, since extended gaps can change tolerability and some prescribers restart at a lower dose.
  ESCALATE: YELLOW.
  LOG: gap_weeks count.
  SOURCE: General GLP-1 titration/tolerability principles reflected across product labels (re-escalation of GI side effects after treatment gaps).
```

**Escalation Conditions:** >= 2 consecutive missed doses; user unsure how many doses they've missed (context ambiguity => ask, do not guess).

**Follow-up Logic:** Confirm next injection occurred as planned (1 reminder at next scheduled date).

---

### 5.3 `MED.INJ_TECHNIQUE` — Injection Technique

**Goal:** Reinforce labeled injection technique; identify technique errors that could cause site issues or dosing inaccuracy.

**Required Inputs:** Specific technique question or described behavior (e.g., angle, whether air bubble is a problem, reusing needles).

**Required Patient Context:** `medication.name` (device type differs: pen vs. vial/syringe), `injection.history`.

**Default Risk Level:** GREEN. Upgrades to YELLOW if technique described suggests intramuscular injection, reuse of needles, or repeated failed doses.

**Decision Rules:**
```
RULE MED.INJ_TECHNIQUE.1
IF user asks about injection sites
THEN
  RECOMMEND: Approved sites per label are abdomen, thigh, or upper arm (subcutaneous); rotate sites each week.
  SOURCE: FDA Prescribing Information, Dosage and Administration section.

RULE MED.INJ_TECHNIQUE.2
IF user describes reusing needles/pens beyond single use
THEN
  RECOMMEND: Single-use only per label; reuse increases infection and dosing-accuracy risk.
  ESCALATE: YELLOW if user reports signs of site infection (redness, warmth, pus, fever) — route to SE protocol 5.14.
  SOURCE: FDA Instructions for Use.

RULE MED.INJ_TECHNIQUE.3
IF user reports visible particulate, cloudiness, or discoloration in the solution
THEN
  RECOMMEND: Do not use; solution should be clear and colorless (or as specified for the product); contact pharmacy for replacement.
  SOURCE: FDA Prescribing Information, Dosage and Administration.

RULE MED.INJ_TECHNIQUE.4
IF user asks whether a partial/incomplete dose "counted"
THEN
  RECOMMEND: Cannot determine dose delivered from a self-report; advise contacting prescriber/pharmacist about whether to treat as a missed dose (route to MED.MISSED logic) rather than guessing.
  ESCALATE: YELLOW.
```

**Escalation Conditions:** Suspected intramuscular injection with pain/bruising; repeated dosing errors.

**Follow-up Logic:** None for GREEN; single check-in for YELLOW technique-correction cases at next injection.

---

### 5.4 `MED.INJ_SITE` — Injection Site Issues

**Goal:** Triage local site reactions (expected/mild vs. concerning).

**Required Inputs:** Description of site appearance (redness, swelling, warmth, size, pain level, duration, discharge, fever).

**Required Patient Context:** `injection.history` (site rotation pattern).

**Default Risk Level:** GREEN for mild, transient redness/itching lasting < 48h with no other symptoms. YELLOW for larger/persistent reactions. RED for infection signs with systemic symptoms.

**Decision Rules:**
```
RULE MED.INJ_SITE.1
IF localized redness/itching, diameter < 2.5 cm, no warmth/fever, present < 48h
THEN
  RECOMMEND: Expected mild injection-site reaction; cool compress, avoid re-injecting same spot, rotate sites.
  LOG: reaction size, duration.

RULE MED.INJ_SITE.2
IF redness/swelling persists > 1 week OR diameter >= 2.5 cm OR increasing in size
THEN
  RECOMMEND: Monitor closely; document with photo if app supports it; contact prescriber if not improving.
  ESCALATE: YELLOW.
  FOLLOW_UP: 3-5 days.

RULE MED.INJ_SITE.3
IF warmth + spreading redness + fever OR pus/discharge
THEN
  RECOMMEND: Signs consistent with possible skin infection (cellulitis); seek prompt medical care (same-day).
  ESCALATE: RED.
  SOURCE: General wound/injection-site infection standard of care.

RULE MED.INJ_SITE.4
IF user reports a firm lump/nodule that persists across weeks at rotated sites (lipohypertrophy pattern)
THEN
  RECOMMEND: Consistent with lipohypertrophy from repeated injection in overlapping areas; reinforce site rotation; advise prescriber awareness at next visit (non-urgent).
  ESCALATE: none (GREEN/YELLOW borderline, default YELLOW if affecting dosing consistency).
```

**Follow-up Logic:** YELLOW cases get a 3-5 day check; RED cases get a same-day wellness check.

---

### 5.5 `MED.INJ_TIMING` — Injection Timing

**Goal:** Answer questions about changing injection day/time.

**Default Risk Level:** GREEN.

**Decision Rules:**
```
RULE MED.INJ_TIMING.1
IF user wants to change their weekly injection day
THEN
  RECOMMEND: Day can generally be changed as long as the interval since the last dose is at least the product-specific minimum (commonly >= 72 hours / 3 days for tirzepatide products per label); confirm against the specific product label at rule-config time.
  SOURCE: Product-specific FDA Medication Guide.

RULE MED.INJ_TIMING.2
IF proposed new day would result in < minimum interval since last dose
THEN
  RECOMMEND: Do not inject early; wait until at least the minimum interval has passed, then resume on the new day going forward.
  ESCALATE: none (GREEN, corrective guidance).
```

---

### 5.6 `MED.STORAGE` — Medication Storage

**Goal:** Answer refrigeration/room-temperature/expiration questions.

**Default Risk Level:** GREEN, upgraded to YELLOW if user reports storage conditions that may have compromised potency/sterility close to a scheduled dose (e.g., pen left in a hot car for hours) and no replacement is available before the dose is due.

**Decision Rules:**
```
RULE MED.STORAGE.1
IF user asks standard storage question (fridge vs. room temp, how long out of fridge)
THEN
  RECOMMEND: Provide the product-specific label storage parameters (typical pattern: refrigerated until first use, then a limited room-temperature window before disposal — exact durations vary by product/pen type and must be sourced from the current label).
  SOURCE: Product-specific FDA Instructions for Use.

RULE MED.STORAGE.2
IF user reports exposure to freezing temperatures, or storage beyond the labeled room-temperature window
THEN
  RECOMMEND: Do not use; potency cannot be assured; contact pharmacy for guidance/replacement before next dose.
  ESCALATE: YELLOW.
```

---

### 5.7 `MED.TRAVEL` — Travel

**Goal:** Support travel logistics (carrying medication, TSA rules, time-zone dosing).

**Default Risk Level:** GREEN.

**Decision Rules:**
```
RULE MED.TRAVEL.1
IF user asks about carrying medication through security/on flights
THEN
  RECOMMEND: General guidance to carry in original packaging with prescription label, keep in carry-on (not checked baggage, due to temperature extremes), bring a cooling case if refrigeration needed for extended travel; confirm current transport-authority rules independently as these can change.
  SOURCE: General pharmacy travel guidance; product Instructions for Use re: temperature limits.

RULE MED.TRAVEL.2
IF user is crossing time zones and asks whether/when to inject
THEN
  RECOMMEND: Route to MED.INJ_TIMING logic — dose is weekly, not tied to local clock time; maintain at least the minimum labeled interval between doses regardless of time zone.
```

**See also:** Section 6.13 Edge Cases (multi-time-zone travel).

---

### 5.8 `MED.INTERACTIONS` — Medication Interactions

**Goal:** Provide general, labeled interaction information; never confirm safety of a specific combination as a substitute for pharmacist/prescriber review.

**Required Inputs:** Name of the other medication/supplement.

**Required Patient Context:** `medication.name`, `contraindications.known`, any known concurrent insulin/sulfonylurea use (for hypoglycemia risk).

**Default Risk Level:** GREEN for general questions; YELLOW when the other substance is a known interacting class (insulin, sulfonylureas, warfarin, oral hormonal contraceptives with tirzepatide, other GLP-1/GIP products).

**Decision Rules:**
```
RULE MED.INTERACTIONS.1
IF user is on insulin or a sulfonylurea AND asks about combining with GLP-1/GIP therapy
THEN
  RECOMMEND: This combination raises hypoglycemia risk; insulin/sulfonylurea doses are often adjusted by the prescriber when starting GLP-1 therapy; confirm current insulin/sulfonylurea dosing with prescriber. Provide hypoglycemia warning-sign education.
  ESCALATE: YELLOW.
  SOURCE: FDA Prescribing Information — Drug Interactions / Warnings and Precautions (hypoglycemia with concomitant insulin secretagogues).

RULE MED.INTERACTIONS.2
IF user asks about oral hormonal contraceptives while on tirzepatide
THEN
  RECOMMEND: Tirzepatide can delay gastric emptying and may reduce absorption of oral contraceptives, particularly during dose escalation; a non-oral or barrier method is often recommended during that period — confirm specifics with prescriber.
  SOURCE: Tirzepatide product labeling guidance on oral contraceptive interaction.

RULE MED.INTERACTIONS.3
IF user asks about coadministering with another GLP-1 or GIP/GLP-1 product (including compounded versions)
THEN
  RECOMMEND: Coadministration with another semaglutide/tirzepatide-containing or other GLP-1 receptor agonist product is not recommended.
  ESCALATE: YELLOW if user indicates they are currently doing this.
  SOURCE: FDA Prescribing Information, Limitations of Use.

RULE MED.INTERACTIONS.4
IF user asks about a medication/supplement not in the known-interaction list
THEN
  RECOMMEND: Provide general mechanism education (e.g., delayed gastric emptying can affect absorption timing of some oral drugs) without asserting safety; direct to pharmacist/prescriber for a definitive interaction check.
  LOG: unresolved interaction query for pharmacology content review (Section 15 change-log candidate).

RULE MED.INTERACTIONS.5
IF user asks about alcohol
THEN
  RECOMMEND: No specific contraindication in labeling, but alcohol can worsen GI side effects, affect blood sugar (especially if on insulin/sulfonylureas), and compound dehydration risk; moderation guidance.
  LOG: none unless combined with hypoglycemia risk context (then route to MED.INTERACTIONS.1 messaging as well).
```

**Escalation Conditions:** Any concurrent insulin/sulfonylurea + new/increasing GLP-1 dose; any stated multi-agonist stacking.

**Follow-up Logic:** YELLOW cases get a check that prescriber was consulted, timed to the user's next dose.

---

### 5.9 `MED.INSURANCE` — Insurance / Prescription Navigation

**Goal:** Non-clinical logistical support (coverage, prior authorization, manufacturer savings programs, pharmacy switching, compounded-product caution).

**Default Risk Level:** GREEN, with a specific YELLOW branch for compounded/unregulated product safety.

**Decision Rules:**
```
RULE MED.INSURANCE.1
IF user asks about coverage/cost/savings programs
THEN
  RECOMMEND: Point to manufacturer savings card programs and pharmacy benefit navigation resources; this is administrative, not clinical, guidance.

RULE MED.INSURANCE.2
IF user mentions switching to a compounded or non-FDA-approved version due to cost/shortage
THEN
  RECOMMEND: Flag that compounded GLP-1 products are not FDA-approved, may have unverified dosing/purity, and switching products/formulations should be discussed with the prescriber.
  ESCALATE: YELLOW.
  SOURCE: FDA public communications on compounded semaglutide/tirzepatide products.

RULE MED.INSURANCE.3
IF user reports a medication shortage affecting their ability to get their prescribed dose
THEN
  RECOMMEND: Contact prescriber/pharmacy about shortage-specific guidance (e.g., alternate dose strengths, extending interval per clinician instruction only); do not self-select a substitute product or dose.
  ESCALATE: YELLOW.
  See also Section 6.13 Edge Cases — Medication Shortages.
```

---

### 5.10 `LIFE.NUTRITION` — Nutrition (General)

**Goal:** Provide general, non-prescriptive nutrition education aligned with obesity-medicine best practice while on GLP-1 therapy; never provide a restrictive numeric diet plan for a user showing disordered-eating signals (see Section 6.3 and cross-reference PSY.WELLBEING).

**Required Patient Context:** `nutrition.food_log_summary` (if opted in), `weight.trend`, any disordered-eating flags in `symptoms.history`.

**Default Risk Level:** GREEN. Upgrades to YELLOW if the request pattern suggests restrictive/compensatory intent (see 5.19/5.20 cross-reference) or the user reports very low intake alongside GI side effects.

**Decision Rules:**
```
RULE LIFE.NUTRITION.1
IF general "what should I eat" question with no disordered-eating flags
THEN
  RECOMMEND: General education — protein-forward, high-fiber, adequate hydration, smaller/more frequent meals if appetite is reduced; link to LIFE.PROTEIN and LIFE.HYDRATION protocols as relevant.

RULE LIFE.NUTRITION.2
IF user describes eating very little (e.g., under ~800 kcal/day self-estimated, or skipping meals most days) without vomiting/nausea explaining it
THEN
  RECOMMEND: Flag that appetite suppression this pronounced should be discussed with the care team to ensure adequate nutrition; avoid specific calorie targets in the response.
  ESCALATE: YELLOW.
  See disordered-eating safety constraint, Section 10.

RULE LIFE.NUTRITION.3
IF user asks about a specific restrictive diet trend layered on top of GLP-1 therapy (e.g., very-low-calorie or prolonged fasting)
THEN
  RECOMMEND: Combining aggressive caloric restriction with GLP-1 therapy increases risk of nutritional deficiency and muscle loss; recommend discussing any structured restrictive diet with prescriber/dietitian first.
  ESCALATE: YELLOW.
```

**Follow-up Logic:** YELLOW nutrition-adequacy flags get a 1-week check-in.

---

### 5.11 `LIFE.PROTEIN` — Protein Intake

**Goal:** Support adequate protein intake to mitigate lean-mass loss during GLP-1-associated weight loss.

**Default Risk Level:** GREEN.

**Decision Rules:**
```
RULE LIFE.PROTEIN.1
IF user asks how much protein they need
THEN
  RECOMMEND: General education that adequate protein intake helps preserve lean mass during weight loss; exact target should come from a dietitian/prescriber based on body weight and goals — the app may show general population ranges as education only, not an individualized prescription.

RULE LIFE.PROTEIN.2
IF nutrition.food_log_summary shows protein consistently far below general reference ranges over 2+ weeks
THEN
  RECOMMEND (personalization layer): Surface the trend and general education about lean-mass preservation; suggest simple protein-forward swaps.
  LOG: trend flag for progress-interpretation cross-reference (5.17).
```

---

### 5.12 `LIFE.HYDRATION` — Hydration

**Goal:** Support adequate fluid intake, particularly relevant given GI-side-effect-driven dehydration/AKI risk (Section 5.13-5.14, 10).

**Default Risk Level:** GREEN. Upgrades per SE.NAUSEA/SE.VOMITING/SE.DIARRHEA rules when hydration is compromised.

**Decision Rules:**
```
RULE LIFE.HYDRATION.1
IF general hydration question, no active GI symptoms
THEN
  RECOMMEND: General fluid-intake education; note GLP-1/GIP therapy can blunt thirst cues alongside appetite, so proactive fluid intake matters.

RULE LIFE.HYDRATION.2
IF hydration.avg_daily_l is available and trending low AND no active GI symptoms
THEN
  RECOMMEND (personalization layer): Reflect the logged average back to the user with a general "consider increasing toward typical reference ranges if appropriate for you" framing — never a hard numeric prescription.

RULE LIFE.HYDRATION.3
IF hydration question co-occurs with active vomiting/diarrhea
THEN
  Route to SE.VOMITING (5.14) / SE.DIARRHEA (5.16) dehydration-risk logic; do not answer as a standalone lifestyle question.
```

---

### 5.13 `LIFE.EXERCISE` — Exercise

**Goal:** General activity education; flag exercise-related red flags (chest pain, severe dizziness during exertion) to emergency protocol.

**Default Risk Level:** GREEN.

**Decision Rules:**
```
RULE LIFE.EXERCISE.1
IF general "what exercise is good" question
THEN
  RECOMMEND: General education — combining resistance training with aerobic activity supports lean-mass preservation during GLP-1-associated weight loss; start gradually, especially if new to exercise.

RULE LIFE.EXERCISE.2
IF user reports chest pain, severe shortness of breath, fainting, or palpitations during/after exercise
THEN
  Route to CLIN.EMERGENCY (5.22).
  ESCALATE: RED.

RULE LIFE.EXERCISE.3
IF user on insulin/sulfonylurea reports lightheadedness/shakiness during exercise
THEN
  RECOMMEND: Possible exercise-associated hypoglycemia; check blood glucose if able; general hypoglycemia self-treatment education; contact prescriber about activity-related dose timing.
  ESCALATE: YELLOW (RED if accompanied by confusion/loss of consciousness risk — route to 5.22).
```

---

### 5.14 `LIFE.SLEEP` — Sleep

**Goal:** General sleep-hygiene education; identify possible sleep apnea signal (relevant given tirzepatide's OSA indication) for prescriber follow-up.

**Default Risk Level:** GREEN.

**Decision Rules:**
```
RULE LIFE.SLEEP.1
IF general sleep-quality question
THEN
  RECOMMEND: Standard sleep-hygiene education.

RULE LIFE.SLEEP.2
IF user reports loud snoring, witnessed breathing pauses, or persistent daytime fatigue despite adequate sleep duration
THEN
  RECOMMEND: These can be signs of obstructive sleep apnea, which is common in obesity and has an FDA-approved GLP-1-class treatment indication in some products; suggest discussing with prescriber, who may recommend a sleep evaluation.
  ESCALATE: YELLOW.
  SOURCE: Tirzepatide (Zepbound) FDA-approved indication for moderate-to-severe obstructive sleep apnea in adults with obesity.
```

---

### 5.15 `LIFE.COACHING` — General Lifestyle Coaching

**Goal:** Catch-all for motivational/behavioral coaching questions not covered by a more specific lifestyle protocol.

**Default Risk Level:** GREEN.

**Decision Rules:**
```
RULE LIFE.COACHING.1
IF user asks for general motivation/habit-building support
THEN
  RECOMMEND: Standard behavior-change coaching content (goal-setting, habit stacking, self-monitoring benefits); no clinical claims.

RULE LIFE.COACHING.2
IF coaching request reveals an underlying clinical concern (e.g., "I keep failing because I feel so sick all the time")
THEN
  Reclassify/route the symptom component to the relevant SE.* protocol; do not answer purely motivationally when a clinical signal is embedded.
```

---

### 5.16 `PROG.WEIGHT_TRACK` — Weight Tracking

**Goal:** Support logging and display of weight trend without over-interpreting single data points.

**Default Risk Level:** GREEN.

**Decision Rules:**
```
RULE PROG.WEIGHT_TRACK.1
IF user logs a weight entry
THEN
  RECOMMEND: Acknowledge, update trend; no interpretation unless user asks (route interpretation requests to PROG.INTERPRET, 5.18).

RULE PROG.WEIGHT_TRACK.2
IF single-entry day-to-day fluctuation is within normal physiological variance (e.g., water-weight range) and user expresses distress about it
THEN
  RECOMMEND: General education on normal day-to-day weight fluctuation (hydration, sodium, hormonal cycles, bowel movements) versus meaningful trend, which is best judged over weeks.

RULE PROG.WEIGHT_TRACK.3
IF logged weight reflects a rapid drop inconsistent with expected pace (e.g., > ~2%/week sustained) 
THEN
  RECOMMEND: Flag for prescriber awareness — rapid weight loss can sometimes indicate inadequate intake, illness, or another cause worth discussing.
  ESCALATE: YELLOW.
```

---

### 5.17 `PROG.PLATEAU` — Weight Plateau

**Goal:** Normalize plateaus as an expected physiological phase while screening for correctable factors and disordered-eating-driven compensatory behavior.

**Required Patient Context:** `weight.trend` (define plateau operationally, e.g., <1% change over >= 3-4 weeks), `nutrition.food_log_summary`, `activity.summary`, adherence pattern.

**Default Risk Level:** GREEN. Upgrades to YELLOW if plateau questions are accompanied by compensatory-behavior language (see Section 10, Section 6.3).

**Decision Rules:**
```
RULE PROG.PLATEAU.1
IF weight.trend meets plateau definition AND no compensatory-behavior flags
THEN
  RECOMMEND: Normalize plateaus as a common, expected part of the weight-loss process (metabolic adaptation); review adherence, nutrition, activity, sleep, hydration as reviewable factors; avoid guaranteeing future loss.

RULE PROG.PLATEAU.2
IF user asks whether they should increase dose to break a plateau
THEN
  Route to MED.DOSE.3 logic — dose changes are prescriber-directed only.

RULE PROG.PLATEAU.3
IF plateau question includes language suggesting compensatory restriction/purging/over-exercise in response to the plateau
THEN
  Route primarily to PSY.WELLBEING / disordered-eating safety constraint (Section 10); do not provide additional restriction-oriented tips.
  ESCALATE: YELLOW minimum.
```

**Follow-up Logic:** Standard plateau discussion gets a 2-3 week trend re-check.

---

### 5.18 `PROG.INTERPRET` — Progress Interpretation

**Goal:** Help users understand what their logged data (weight, symptoms, adherence) means in context, strictly within educational bounds — never a clinical prognosis.

**Default Risk Level:** GREEN.

**Decision Rules:**
```
RULE PROG.INTERPRET.1
IF user asks "is this normal / am I doing okay" with a specific data point
THEN
  RECOMMEND: Compare the data point against general expected patterns for treatment week/dose (educational ranges only, not individualized medical prognosis); explicitly note that individual variation is wide and their prescriber has the full clinical picture.

RULE PROG.INTERPRET.2
IF requested interpretation would require clinical judgment beyond general pattern description (e.g., "does this mean my liver is being damaged")
THEN
  RECOMMEND: State this requires clinical evaluation (labs, exam) and cannot be answered from tracked app data alone; route to CLIN.LABS (5.21) or prescriber contact as appropriate.
  ESCALATE: YELLOW if underlying symptom is concerning per another protocol.
```

---

### 5.19 `SE.NAUSEA` — Nausea

**Goal:** Triage the most common GLP-1 side effect; distinguish routine/expected nausea from a pattern suggesting dehydration, pancreatitis, or another serious cause.

**Required Inputs (Missing-Information Protocol):**
- Current medication and dose
- Week of treatment / time since last dose change
- Vomiting present? (routes to 5.20 if yes and significant)
- Able to keep fluids down?
- Abdominal pain present? Location/severity/radiation?
- Fever?
- Pregnancy status (if applicable demographic)
- Blood sugar history (if diabetic/on insulin or sulfonylurea)
- Duration of this episode
- Severity (mild/moderate/severe, e.g., via a 1-10 scale or functional impact)

*Only proceed to Decision Rules once this set is collected or already current in Patient Context; if the user is clearly distressed, ask the minimum subset needed for triage (fluids down? abdominal pain? fever?) before the full set.*

**Required Patient Context:** `medication.name`, `medication.current_dose_mg`, `medication.treatment_week`, `medication.last_injection_date` (proximity to dose escalation), `demographics.pregnancy_status`, contraindications re: diabetes/insulin.

**Default Risk Level:** GREEN for mild, early-treatment or post-dose-increase nausea with no red flags. YELLOW for persistent/moderate nausea impairing intake without red flags. RED for nausea plus severe abdominal pain, inability to keep fluids down, or other RED modifiers.

**Decision Rules:**
```
RULE SE.NAUSEA.1
IF mild-moderate nausea AND within first 4 weeks of starting OR within 1 week of a dose increase AND no vomiting AND fluids tolerated AND no severe abdominal pain/fever
THEN
  RECOMMEND: Common, expected, typically transient side effect, more prevalent at initiation/dose escalation; general measures — smaller/lower-fat meals, eating slowly, avoiding lying down right after eating, ginger/mint as commonly used comfort measures, adequate hydration.
  SOURCE: FDA Prescribing Information adverse reactions section (nausea most common GI adverse reaction, most prevalent during dose escalation); general GI side-effect management guidance.
  FOLLOW_UP: 5-7 days.

RULE SE.NAUSEA.2
IF nausea persists > 1-2 weeks without improvement, or is rated moderate-severe and limiting oral intake, with no RED modifiers
THEN
  RECOMMEND: Continue supportive measures; recommend contacting prescriber to discuss (may include slowing titration pace, or in some cases an antiemetic — prescriber decision only).
  ESCALATE: YELLOW.
  FOLLOW_UP: 3-4 days.

RULE SE.NAUSEA.3
IF nausea accompanies severe, persistent abdominal pain (especially radiating to the back) with or without vomiting
THEN
  RECOMMEND: This combination can be a sign of pancreatitis, a rare but serious risk associated with GLP-1 therapy; seek prompt medical evaluation (same-day/urgent care or ED depending on severity).
  ESCALATE: RED.
  SOURCE: FDA Prescribing Information, Warnings and Precautions — Acute Pancreatitis; discontinue promptly if pancreatitis is suspected (prescriber/ED decision).

RULE SE.NAUSEA.4
IF nausea accompanies right-upper-quadrant abdominal pain, fever, and/or jaundice
THEN
  RECOMMEND: This combination can indicate a gallbladder/biliary problem, a known risk with GLP-1 therapy; seek prompt medical evaluation.
  ESCALATE: RED.
  SOURCE: Evidence linking GLP-1 receptor agonist use to increased gallbladder/biliary disease risk (systematic review/meta-analysis literature); FDA labeling on cholelithiasis/cholecystitis.

RULE SE.NAUSEA.5
IF nausea is preventing any fluid intake for >= 24 hours, or user reports dark urine/reduced urination/dizziness alongside nausea
THEN
  Route to SE.VOMITING dehydration/AKI logic (5.20.4) regardless of vomiting status.
  ESCALATE: RED.

RULE SE.NAUSEA.6
IF user is pregnant or trying to conceive and reports nausea
THEN
  RECOMMEND: Nausea in pregnancy has other important causes to evaluate; also flag pregnancy + GLP-1 therapy for prescriber discussion per CLIN.PREGNANCY (5.23).
  ESCALATE: YELLOW minimum (RED if severe/hyperemesis pattern — inability to keep fluids down).

RULE SE.NAUSEA.7
IF user is on insulin/sulfonylurea and nausea is reducing food intake
THEN
  RECOMMEND: Reduced intake can raise hypoglycemia risk when on insulin/sulfonylurea; check blood sugar more frequently per prescriber guidance; contact prescriber about possible insulin/sulfonylurea dose adjustment (prescriber decision only).
  ESCALATE: YELLOW.
  SOURCE: FDA labeling — hypoglycemia risk with concomitant insulin secretagogues.
```

**Follow-up Logic:** GREEN nausea gets a 5-7 day passive check; YELLOW gets 3-4 day active check with escalation if unresolved or worsening; RED gets an urgent wellness check within hours.

---

### 5.20 `SE.VOMITING` — Vomiting

**Goal:** Triage vomiting with heightened attention to dehydration/AKI risk — the best-documented serious-adverse-event pathway for GI side effects in this drug class.

**Required Inputs:** Frequency/episodes in last 24h, ability to keep any fluids down, presence of blood in vomit, abdominal pain, fever, urination pattern (frequency/color), dizziness/lightheadedness, pregnancy status, diabetes/insulin status, duration.

**Required Patient Context:** Same as 5.19, plus recent GI-symptom history (compounding effect of concurrent diarrhea).

**Default Risk Level:** YELLOW by default (vomiting is treated more conservatively than nausea alone). RED with any dehydration/pancreatitis/GI-bleed modifier.

**Decision Rules:**
```
RULE SE.VOMITING.1
IF isolated vomiting episode(s) (1-2 in 24h), fluids tolerated between episodes, no blood, no severe pain, no dizziness/reduced urination
THEN
  RECOMMEND: Sip clear fluids slowly, bland diet as tolerated, rest; monitor for worsening.
  ESCALATE: YELLOW (default per protocol).
  FOLLOW_UP: same-day or next-day check.

RULE SE.VOMITING.2
IF unable to keep any fluids down for >= 24 hours
THEN
  RECOMMEND: Risk of dehydration and kidney injury; seek prompt medical evaluation (urgent care/ED) for IV fluids if unable to rehydrate orally.
  ESCALATE: RED.
  SOURCE: FDA-mandated GLP-1 class labeling on acute kidney injury associated with GI-adverse-reaction-driven dehydration (nausea, vomiting, diarrhea); postmarketing reports of AKI, some requiring hemodialysis, predominantly in patients who experienced these GI reactions.

RULE SE.VOMITING.3
IF vomiting accompanies dark urine, significantly reduced urination, dizziness/lightheadedness, or confusion
THEN
  RECOMMEND: These are signs of possible dehydration/kidney injury; seek prompt medical evaluation now.
  ESCALATE: RED.
  SOURCE: FDA GLP-1 class kidney-injury warning; patients advised to seek care at first sign of dehydration or kidney issues (dark urine, infrequent urination, dizziness).

RULE SE.VOMITING.4
IF vomiting is accompanied by severe abdominal pain (especially radiating to back)
THEN
  Route to SE.NAUSEA.3 pancreatitis escalation logic.
  ESCALATE: RED.

RULE SE.VOMITING.5
IF vomit contains blood or looks like coffee grounds
THEN
  RECOMMEND: Seek emergency care now.
  ESCALATE: RED.

RULE SE.VOMITING.6
IF vomiting recurs across multiple days (>= 3 days) even if individually mild
THEN
  RECOMMEND: Persistent vomiting beyond a few days should be evaluated by the prescriber even without acute red flags, both for cause and to prevent cumulative dehydration.
  ESCALATE: YELLOW, trending toward RED if unresolved at follow-up.
  FOLLOW_UP: daily check until resolved or escalated.

RULE SE.VOMITING.7
IF user is on insulin/sulfonylurea and vomiting is preventing normal food intake
THEN
  RECOMMEND: Elevated hypoglycemia risk; check blood glucose more frequently; contact prescriber about insulin/sulfonylurea adjustment (prescriber decision only); if any confusion, shakiness with low measured glucose, or loss of consciousness risk, treat as emergency.
  ESCALATE: YELLOW minimum, RED if altered mental status present (route to 5.22).
```

**Escalation Conditions:** Any dehydration sign; any GI bleed sign; any pancreatitis-pattern pain; >=3 day duration.

**Follow-up Logic:** Daily check-ins until resolution for YELLOW; urgent wellness check for RED.

---

### 5.21 `SE.CONSTIPATION` — Constipation

**Goal:** Manage a common, usually self-limited side effect; screen for bowel-obstruction pattern.

**Required Inputs:** Duration, last bowel movement, presence of bloating/distension, presence of any gas passage, abdominal pain, nausea/vomiting co-occurrence, fiber/fluid/activity habits.

**Default Risk Level:** GREEN for typical constipation with ongoing gas passage and no significant pain. RED for suspected obstruction pattern.

**Decision Rules:**
```
RULE SE.CONSTIPATION.1
IF infrequent stools, mild discomfort, still passing gas, no vomiting, no severe distension
THEN
  RECOMMEND: General measures — increase fiber gradually, increase fluid intake, regular physical activity; over-the-counter options are a personal/prescriber decision, not an app-issued recommendation of a specific product/dose.
  FOLLOW_UP: 1 week.

RULE SE.CONSTIPATION.2
IF no bowel movement for >= 5-7 days despite general measures, or worsening abdominal distension
THEN
  RECOMMEND: Contact prescriber; may need evaluation or a specific bowel regimen recommendation.
  ESCALATE: YELLOW.

RULE SE.CONSTIPATION.3
IF no bowel movement AND no gas passage AND significant bloating/distension AND vomiting
THEN
  RECOMMEND: This pattern can indicate bowel obstruction, which requires emergency evaluation.
  ESCALATE: RED.
```

---

### 5.22 `SE.DIARRHEA` — Diarrhea

**Goal:** Manage a common GI side effect; monitor for dehydration given its contribution to the class AKI risk.

**Required Inputs:** Frequency/day, duration, blood/mucus in stool, fever, abdominal pain, hydration status, co-occurring vomiting.

**Default Risk Level:** GREEN for mild/brief. YELLOW for persistent/moderate. RED for dehydration signs or bloody diarrhea/high fever.

**Decision Rules:**
```
RULE SE.DIARRHEA.1
IF mild, <= 2 days duration, no blood, no fever, adequately hydrated
THEN
  RECOMMEND: Supportive measures — hydration with electrolytes, bland diet, monitor.
  FOLLOW_UP: 2-3 days.

RULE SE.DIARRHEA.2
IF persists > 3 days, or frequent (>= 5-6 episodes/day)
THEN
  RECOMMEND: Contact prescriber; risk of dehydration rises with duration/frequency.
  ESCALATE: YELLOW.

RULE SE.DIARRHEA.3
IF diarrhea + reduced urination/dark urine/dizziness (dehydration signs)
THEN
  Route to SE.VOMITING.3 dehydration/AKI RED logic.
  ESCALATE: RED.

RULE SE.DIARRHEA.4
IF blood/mucus in stool, or high fever, or severe abdominal pain
THEN
  RECOMMEND: Seek prompt medical evaluation.
  ESCALATE: RED.
```

---

### 5.23 `SE.HEARTBURN` — Heartburn / Reflux

**Goal:** Manage a common, usually mild GI side effect related to delayed gastric emptying; screen for atypical chest-pain presentation.

**Default Risk Level:** GREEN. Immediate reroute to RED for chest-pain ambiguity.

**Decision Rules:**
```
RULE SE.HEARTBURN.1
IF classic burning sensation after meals, no chest tightness/pressure/radiation/shortness of breath/sweating
THEN
  RECOMMEND: General measures — smaller meals, avoid lying down for ~2-3h after eating, limit trigger foods (fatty/spicy/acidic), elevate head of bed; discuss persistent symptoms with prescriber for antacid/other therapy guidance (not app-recommended dosing).
  FOLLOW_UP: 1 week if persistent.

RULE SE.HEARTBURN.2
IF any ambiguity between "heartburn" and cardiac chest pain (pressure/tightness, radiation to arm/jaw, shortness of breath, sweating, dizziness), especially in a user with cardiovascular risk factors
THEN
  Route to CLIN.EMERGENCY (5.26).
  ESCALATE: RED.
```

---

### 5.24 `SE.FATIGUE` — Fatigue

**Goal:** General fatigue management; screen for hypoglycemia, dehydration, and severe fatigue patterns warranting evaluation.

**Default Risk Level:** GREEN. YELLOW/RED via modifier rules.

**Decision Rules:**
```
RULE SE.FATIGUE.1
IF mild fatigue, adequate intake/hydration, no other red-flag symptoms
THEN
  RECOMMEND: Can occur especially during dose escalation/early treatment as intake adjusts; monitor sleep, hydration, nutrition adequacy (cross-reference LIFE.SLEEP, LIFE.HYDRATION, LIFE.NUTRITION).

RULE SE.FATIGUE.2
IF fatigue co-occurs with reduced food intake AND user is on insulin/sulfonylurea
THEN
  RECOMMEND: Check blood glucose; fatigue can be a hypoglycemia symptom in this context.
  ESCALATE: YELLOW (RED if confusion/fainting — route to 5.26).
  SOURCE: FDA labeling — hypoglycemia risk with concomitant insulin secretagogues.

RULE SE.FATIGUE.3
IF fatigue is severe, worsening, and persistent (>= 2 weeks) without clear cause
THEN
  RECOMMEND: Warrants prescriber evaluation (could reflect nutritional inadequacy, thyroid changes, anemia, or another cause not determinable from app data).
  ESCALATE: YELLOW.
```

---

### 5.25 `SE.DIZZINESS` — Dizziness

**Goal:** Triage dizziness — commonly benign/dehydration-related but overlapping with several RED patterns.

**Default Risk Level:** YELLOW by default given overlap with dehydration/hypoglycemia/cardiac causes; downgrade to GREEN only for clearly positional, brief, isolated episodes with no other symptoms.

**Decision Rules:**
```
RULE SE.DIZZINESS.1
IF brief, positional (standing up quickly), isolated, no other symptoms, adequate hydration
THEN
  RECOMMEND: Likely orthostatic; rise slowly, ensure adequate hydration/intake; monitor.

RULE SE.DIZZINESS.2
IF dizziness co-occurs with vomiting/diarrhea/reduced urination
THEN
  Route to SE.VOMITING.3 dehydration/AKI RED logic.
  ESCALATE: RED.

RULE SE.DIZZINESS.3
IF user on insulin/sulfonylurea and dizziness co-occurs with reduced intake or known low blood sugar reading
THEN
  RECOMMEND: Treat per standard hypoglycemia guidance if measurable and the user is alert (e.g., fast-acting carbohydrate per their prescriber's hypoglycemia plan); if confusion, fainting, or inability to safely swallow, this is an emergency.
  ESCALATE: YELLOW if alert/oriented and self-treating per known plan; RED if altered mental status (route to 5.26).

RULE SE.DIZZINESS.4
IF dizziness co-occurs with chest pain, severe headache ("worst headache of life"), slurred speech, facial drooping, or limb weakness
THEN
  Route to CLIN.EMERGENCY (5.26).
  ESCALATE: RED.
```

---

### 5.26 `SE.HEADACHE` — Headache

**Goal:** General headache support; screen for neurological emergency patterns.

**Default Risk Level:** GREEN.

**Decision Rules:**
```
RULE SE.HEADACHE.1
IF typical, mild-moderate headache, no neuro symptoms, adequate hydration
THEN
  RECOMMEND: General self-care (hydration, rest); note dehydration from GI side effects can contribute to headache — cross-check hydration/GI status.

RULE SE.HEADACHE.2
IF "worst headache of life," sudden onset/thunderclap, headache with fever + stiff neck, or headache with neuro symptoms (vision loss, weakness, confusion, slurred speech)
THEN
  Route to CLIN.EMERGENCY (5.26).
  ESCALATE: RED.

RULE SE.HEADACHE.3
IF headache is chronic/recurring and not explained by dehydration
THEN
  RECOMMEND: Discuss with prescriber if persistent beyond general self-care.
  ESCALATE: YELLOW.
```

---

### 5.27 `SE.APPETITE` — Appetite Changes

**Goal:** Normalize expected appetite suppression (primary mechanism of the drug class) while screening for excessive suppression risking nutritional inadequacy, and for the opposite pattern (unexpectedly increased hunger/binge episodes) which may signal tolerance, incorrect dosing, or a disordered-eating pattern.

**Default Risk Level:** GREEN for expected suppression. YELLOW for extremes in either direction.

**Decision Rules:**
```
RULE SE.APPETITE.1
IF reduced appetite consistent with expected drug mechanism, intake still adequate
THEN
  RECOMMEND: Expected effect; reinforce nutrient-dense, protein-forward eating despite lower volume (cross-reference LIFE.PROTEIN, LIFE.NUTRITION).

RULE SE.APPETITE.2
IF appetite suppression is severe enough that user reports eating very little for several days
THEN
  Route to LIFE.NUTRITION.2 logic.
  ESCALATE: YELLOW.

RULE SE.APPETITE.3
IF user reports unexpectedly strong hunger/loss of appetite-suppression effect mid-treatment
THEN
  RECOMMEND: Can occur near end of a weekly dosing cycle or with plateauing effect at a given dose; not a signal to self-adjust dose; discuss with prescriber if persistent.
  ESCALATE: GREEN-YELLOW borderline; default YELLOW if distressing to the user.

RULE SE.APPETITE.4
IF user describes binge-eating episodes or loss-of-control eating
THEN
  Route to PSY.EMOTIONAL_EAT (5.28) / disordered-eating safety constraint (Section 10).
  ESCALATE: YELLOW.
```

---

### 5.28 `PSY.EMOTIONAL_EAT` — Emotional Eating

**Goal:** Provide behavioral-coaching-level support for emotional eating patterns; identify when the pattern crosses into a disordered-eating or mental-health concern requiring escalation beyond app scope.

**Default Risk Level:** GREEN for reflective/coaching-level questions. YELLOW/RED per Section 10 disordered-eating and mental-health constraints.

**Decision Rules:**
```
RULE PSY.EMOTIONAL_EAT.1
IF user reflects on emotional eating patterns without describing loss-of-control bingeing, purging, or severe restriction
THEN
  RECOMMEND: Standard behavioral coaching — identifying triggers, alternative coping strategies, self-compassion framing; normalize that this is common and addressable.

RULE PSY.EMOTIONAL_EAT.2
IF user describes recurrent loss-of-control eating episodes (bingeing), compensatory behavior (purging, laxative misuse, compulsive exercise), or fear/preoccupation with food/weight that is distressing and persistent
THEN
  RECOMMEND: Acknowledge the difficulty; explain this pattern is best supported by a clinician/therapist with eating-disorder expertise, ideally in coordination with the prescriber; provide eating-disorder helpline resource information (e.g., National Alliance for Eating Disorders) if requested or as part of standard resource provision — do not provide restrictive dietary guidance in this or future turns in the conversation.
  ESCALATE: YELLOW minimum; RED if accompanied by self-harm risk (route to 5.32) or medically dangerous compensatory behavior (e.g., severe laxative misuse, purging with dehydration signs — route to SE.VOMITING RED logic).
  See Section 10 hard constraint: once this flag fires, the engine suppresses numeric diet/calorie/exercise-target content for the remainder of the conversation.
```

---

### 5.29 `PSY.WELLBEING` — Mental Wellbeing

**Goal:** Provide supportive, validating engagement with mood/mental-health disclosures; screen for crisis risk; never diagnose a mental health condition.

**Default Risk Level:** GREEN for general mood check-ins. RED for any self-harm/suicide signal (highest-priority pre-filter, Section 3.5).

**Decision Rules:**
```
RULE PSY.WELLBEING.1
IF user expresses general low mood, frustration with progress, or body-image distress without crisis indicators
THEN
  RECOMMEND: Validate the difficulty; provide supportive framing; do not attribute the mood to a named diagnosis; suggest that persistent low mood is worth mentioning to their prescriber or a mental health professional, since both obesity treatment and mood are interconnected and best supported together.

RULE PSY.WELLBEING.2
IF user asks whether the medication itself could be affecting their mood
THEN
  RECOMMEND: General education that mood changes have been reported by some patients and are worth discussing with the prescriber to sort out contributing factors; do not confirm causation.
  ESCALATE: YELLOW.
  FOLLOW_UP: 1 week.

RULE PSY.WELLBEING.3
IF user expresses hopelessness, worthlessness, or ideation of self-harm/suicide (any intensity, including passive ideation e.g. "sometimes I wonder what's the point")
THEN
  ESCALATE: RED — handled per Section 3.5 pre-filter and Section 3.4 RED protocol regardless of which intent classifier would otherwise apply.
  RECOMMEND: Provide crisis resources (e.g., 988 Suicide & Crisis Lifeline in the U.S., or local equivalent) in addition to general emergency guidance; maintain a calm, stabilizing, non-judgmental tone; do not end the conversation; do not ask probing questions that could feel like an interrogation.
  FOLLOW_UP: Wellness check per Section 3.4.
```

---

### 5.30 `CLIN.LABS` — Lab Questions

**Goal:** Help users understand lab-related questions (what tests might be relevant, general reference-range education) without interpreting the user's specific results as a diagnosis.

**Default Risk Level:** GREEN. YELLOW if described lab value is significantly abnormal per general reference ranges.

**Decision Rules:**
```
RULE CLIN.LABS.1
IF user asks general question about what labs are typically monitored on GLP-1 therapy
THEN
  RECOMMEND: General education (e.g., A1c/glucose in diabetic patients, periodic metabolic panel, lipid panel as part of routine obesity-medicine care) — not a mandate, since monitoring plans are individualized by the prescriber.

RULE CLIN.LABS.2
IF user reports a specific lab value and asks what it means
THEN
  RECOMMEND: Provide general reference-range context only ("this is above/within/below a typical reference range") without diagnostic interpretation; direct to prescriber for clinical interpretation in the context of their full picture.
  ESCALATE: YELLOW if the value is markedly abnormal by general reference standards (e.g., signs suggestive of significantly impaired kidney function, markedly elevated lipase/amylase suggestive of pancreatitis) — pair with relevant SE protocol if symptoms are also present.

RULE CLIN.LABS.3
IF lab.latest context is available and stale (> 6 months) and clinically relevant to an active question
THEN
  RECOMMEND: Note that labs may be outdated for this question; suggest requesting updated labs from prescriber.
```

---

### 5.31 `CLIN.EDUCATION` — General Education

**Goal:** Answer general "how does this work" / mechanism / what-to-expect questions.

**Default Risk Level:** GREEN.

**Decision Rules:**
```
RULE CLIN.EDUCATION.1
IF general mechanism/what-to-expect question with no personal symptom/risk content
THEN
  RECOMMEND: Provide general, source-grounded educational content (mechanism of action, expected timeline of effects, general safety profile overview) drawn from the current FDA-approved labeling and reputable clinical sources; always paired with the standard "this is general education, not personalized medical advice" framing.

RULE CLIN.EDUCATION.2
IF an educational question edges into a personal risk assessment (e.g., "is this medication safe for someone with my history of X")
THEN
  Reclassify toward the relevant clinical protocol (MED.INTERACTIONS, CLIN.PREGNANCY, etc.) rather than answering generically.
```

---

### 5.32 `CLIN.PREGNANCY` — Pregnancy Questions

**Goal:** Handle pregnancy/conception questions with elevated caution given labeled guidance to discontinue GLP-1 therapy prior to a planned pregnancy and limited human safety data.

**Required Inputs:** Current pregnancy status, trying-to-conceive status, contraception use, last menstrual period if relevant/volunteered.

**Default Risk Level:** YELLOW by default for any pregnancy-adjacent question; RED if user is currently pregnant and actively taking the medication, or reports a positive pregnancy test while on therapy.

**Decision Rules:**
```
RULE CLIN.PREGNANCY.1
IF user is trying to conceive or planning to become pregnant and asks about GLP-1 therapy timing
THEN
  RECOMMEND: Labeling generally recommends discontinuing GLP-1 therapy for a period before a planned pregnancy (specific washout duration varies by product and should be confirmed against the current label — e.g., semaglutide labeling has historically recommended discontinuation approximately 2 months before a planned pregnancy given its long half-life); this must be planned with the prescriber, not self-managed.
  ESCALATE: YELLOW.
  SOURCE: Product-specific FDA Prescribing Information, Use in Specific Populations — Pregnancy; note a pregnancy exposure registry exists for semaglutide-exposed pregnancies.

RULE CLIN.PREGNANCY.2
IF user reports they are currently pregnant and currently taking a GLP-1/GIP medication
THEN
  RECOMMEND: Contact prescriber promptly to discuss discontinuation and pregnancy-appropriate care; do not instruct the user to stop or continue on the app's authority — this is communicated as an urgent care-team conversation, not a self-directed stop instruction, though the app may note that ongoing use during pregnancy is generally not recommended per labeling pending prescriber guidance.
  ESCALATE: RED (time-sensitive clinical coordination needed) — routed to urgent prescriber-contact messaging rather than emergency-services messaging unless an acute symptom is also present.
  SOURCE: Product-specific FDA Prescribing Information, Use in Specific Populations — Pregnancy.

RULE CLIN.PREGNANCY.3
IF user asks general questions about GLP-1 use while breastfeeding
THEN
  RECOMMEND: General education that data are limited; this is a prescriber (and often pediatrician) discussion.
  ESCALATE: YELLOW.
```

**Follow-up Logic:** RED/YELLOW pregnancy cases get a follow-up confirming prescriber contact within 24-48 hours.

---

### 5.33 `MED.INTERACTIONS` (see 5.8) — cross-referenced, not duplicated here.

---

### 5.34 `CLIN.EMERGENCY` — Emergency Symptoms

**Goal:** Route any acute, potentially life-threatening presentation directly to emergency guidance with minimal friction. This protocol is invoked either directly (explicit emergency language) or via routing rules from any other protocol above.

**Default Risk Level:** RED, always.

**Decision Rules:**
```
RULE CLIN.EMERGENCY.1
IF chest pain/pressure, shortness of breath, fainting, stroke symptoms (facial droop, arm weakness, slurred speech), severe allergic reaction (throat/facial swelling, difficulty breathing, widespread hives with dizziness), suicidal/self-harm ideation, vomiting blood, signs of severe dehydration with confusion, or suspected bowel obstruction
THEN
  RECOMMEND: Instruct the user to call emergency services (911 in the U.S. or local equivalent) or go to the nearest emergency department immediately; if a self-harm/suicide signal is present, also provide crisis line resources (e.g., 988) alongside the emergency instruction, never instead of it.
  ESCALATE: RED — terminal, no further app-led triage; no self-care suggestions offered.
  LOG: full detail, high-priority audit flag, provider notification if integration exists.
  FOLLOW_UP: wellness check per Section 3.4.

RULE CLIN.EMERGENCY.2
IF the user indicates they cannot safely contact emergency services themselves (e.g., alone, disabled, describes being unable to act)
THEN
  RECOMMEND: Provide clear, simple, minimal-step instructions (e.g., "if you have a phone nearby, call [emergency number] now; if someone is with you, ask them to call now"); keep language short given potential impairment.
  ESCALATE: RED.
```

**Escalation Conditions:** N/A — this protocol is itself the top of the escalation chain.

**Follow-up Logic:** See Section 3.4.

---

### 5.35 `OTHER` — Uncategorized / Out of Scope

**Goal:** Gracefully handle messages outside the supported taxonomy without pretending to have clinical relevance.

**Default Risk Level:** GREEN, unless the Section 3.5 pre-filter has already flagged risk content, in which case RED protocol takes precedence regardless of topical relevance.

**Decision Rules:**
```
RULE OTHER.1
IF message is unrelated to the application's clinical/lifestyle scope (e.g., small talk, unrelated product questions)
THEN
  RECOMMEND: Respond conversationally within scope limits; offer to help with medication, side effects, nutrition, or progress tracking.

RULE OTHER.2
IF message is ambiguous between OTHER and a real clinical intent
THEN
  Ask one deterministic disambiguation question (Section 2.3) before defaulting to OTHER.
```

---

## 6. Personalization Layer

### 6.1 Principle: Protocol vs. Personalization Are Separate Objects

The Decision Engine (Section 5) always outputs a **Protocol Recommendation** — generic, evidence-sourced, identical for every user in that rule state. The Personalization Layer then decorates that recommendation with the user's own logged data, without altering its clinical substance (P11). This separation is what keeps the system testable: protocol correctness is tested against fixed inputs (Section 14); personalization correctness is tested separately against data-binding logic.

```
PROTOCOL:        "Increase hydration."
PERSONALIZATION: "You've averaged 1.4 L/day this week — consider increasing
                   toward typical reference ranges of 2-3 L/day if that feels
                   right for you."
```

### 6.2 Personalization Rules

1. Personalization may only cite fields present in Section 4's Patient Context Schema for that user, current as of the interaction.
2. Personalization never introduces a new clinical claim, threshold, or recommendation not already licensed by the fired rule(s).
3. Personalization may reference trend direction (improving/worsening/stable) but may not predict future outcomes ("at this rate you'll hit your goal by...") since this implies a clinical guarantee the engine cannot make.
4. If personalization data is missing or opted out, the engine falls back to the generic protocol text unmodified — it never fabricates a plausible-sounding number.

### 6.3 Personalization Guardrail — Disordered Eating

Numeric personalization (specific calorie counts, macro targets, weight-loss-rate framing) is **suppressed** for any user with an active disordered-eating flag (Section 5.28/10) for the remainder of the conversation, regardless of which protocol subsequently fires. This is a hard filter applied after rule evaluation and before composer handoff.

---

## 7. Response Requirements

### 7.1 Mandatory Components

Every user-facing response assembled by the AI Composer from engine output must include, as applicable to the risk tier:

| Component | GREEN | YELLOW | RED |
|---|---|---|---|
| Empathetic acknowledgment | Yes | Yes | Yes (brief, non-delaying) |
| Clinical/educational content | Yes | Yes | No (emergency instructions only) |
| Recommended actions (protocol-sourced only) | Yes | Yes | Emergency action only |
| Monitoring instructions ("watch for X") | Optional | Yes | N/A |
| Escalation guidance (when/how to contact care team or emergency services) | Boilerplate | Explicit, timeboxed | Explicit, immediate |
| Expected timeline (when to expect improvement / when to worry if it doesn't) | Optional | Yes | N/A |
| Confidence/uncertainty statement (when classification confidence was borderline or information was incomplete) | If applicable | If applicable | If applicable |
| "Not a substitute for your care team" reminder | Yes (light-touch) | Yes | Implicit in emergency routing |

### 7.2 Prohibited Content in Any Response

- Named diagnoses.
- Specific dosing instructions beyond FDA-labeled missed-dose/injection-day guidance.
- Definitive interaction "safety" confirmations.
- Predictions of outcome/timeline guarantees.
- Any content contradicting `provider.instructions` when present.

### 7.3 Tone Requirements

Empathetic, non-alarmist for GREEN/YELLOW; calm, direct, and action-first for RED (no extended preamble before the emergency instruction).

### 7.4 Explainability Payload

Every response is generated alongside a machine-readable trace object, not shown to the user but stored for audit and available to a provider-facing dashboard if applicable:

```json
{
  "message_id": "string",
  "protocol_version": "string",
  "intent_primary": "string",
  "intent_secondary": ["string"],
  "intent_confidence": 0.00,
  "risk_tier": "GREEN|YELLOW|RED",
  "risk_modifiers_fired": ["string"],
  "rules_fired": ["SE.NAUSEA.3", "..."],
  "missing_info_requested": ["string"],
  "patient_context_snapshot_id": "string",
  "personalization_fields_used": ["string"],
  "escalation_action": "none|contact_provider_24h|contact_provider_72h|emergency",
  "follow_up_scheduled": {"type": "string", "due_at": "ISO8601"}
}
```

---

## 8. Memory Updates

### 8.1 Principle

The engine **never** re-reads raw conversation transcript to reconstruct clinical state (P10, P11 support). Every interaction writes a structured memory record; all future context retrieval (Section 4) reads from these structured records, not from re-parsed chat history.

### 8.2 Structured Record Schema

```json
{
  "record_id": "string",
  "user_id": "string",
  "timestamp": "ISO8601",
  "intent_primary": "string",
  "intent_secondary": ["string"],
  "risk_tier": "GREEN|YELLOW|RED",
  "symptom": {
    "type": "string|null",
    "severity": "mild|moderate|severe|null",
    "duration": "string|null",
    "modifiers_present": ["string"]
  },
  "advice_provided_summary": "string (protocol-level, not full composer text)",
  "protocol_executed": {"rule_ids": ["string"], "protocol_version": "string"},
  "follow_up_scheduled": {"type": "string", "due_at": "ISO8601|null"},
  "outcome": "unknown|improved|unchanged|worsened|escalated|resolved",
  "resolution_status": "open|monitoring|resolved|escalated_to_provider|escalated_to_emergency"
}
```

### 8.3 Retention and Purge Rules

RED-tier and any disordered-eating/mental-health-flagged records are retained per the organization's clinical/legal retention policy and are never auto-purged by a generic data-retention job. GREEN informational records may follow standard retention policy. All retention rules must be reviewed by legal/compliance, not solely engineering.

---

## 9. Follow-up Engine

### 9.1 Cross-Cutting Rules

While individual timing is specified per protocol (Section 5), the following rules apply globally:

```
RULE FOLLOWUP.1
IF risk_tier == RED
THEN schedule wellness check within 2-4 hours (in-app) or next business day (if channel limited); never skip.

RULE FOLLOWUP.2
IF risk_tier == YELLOW
THEN schedule check-in per protocol-specific interval (typically 24h-1 week); if no response after 2 scheduled attempts, surface a passive in-app prompt rather than silently closing the loop.

RULE FOLLOWUP.3
IF a scheduled YELLOW follow-up reveals worsening or no improvement past the expected timeline
THEN re-run risk classification with the new information; typically escalates to RED or a stronger YELLOW action (e.g., firmer provider-contact recommendation).

RULE FOLLOWUP.4
IF resolution_status becomes "resolved" via user confirmation
THEN stop scheduled reminders for that symptom thread; log final outcome.

RULE FOLLOWUP.5
IF a follow-up would occur outside reasonable contact hours (e.g., 11pm-7am local) for a non-RED item
THEN defer to the next reasonable-hours window; RED wellness checks are never deferred for time-of-day.
```

---

## 10. Safety Constraints

The following are absolute, non-negotiable constraints enforced at multiple layers (rule engine, composer prompt boundary, and output-side classifier/filter as a final backstop):

1. **Never diagnose** a medical or mental health condition.
2. **Never prescribe or recommend starting, stopping, splitting, or changing a medication dose**, beyond restating FDA-labeled missed-dose/injection-day timing rules verbatim.
3. **Never recommend a specific over-the-counter medication, product, or dose** for symptom management (e.g., never "take 500mg of X") — general category guidance only, deferring specifics to pharmacist/prescriber.
4. **Never interpret imaging or definitive lab diagnostic results** as conclusive of a condition.
5. **Never contradict explicit clinician/provider instructions** present in `provider.instructions`.
6. **Never fabricate a citation, statistic, or evidence source.** If the engine cannot ground a claim in a sourced rule, it defaults to general, appropriately hedged educational language and flags the gap for content-team review (Section 15).
7. **Always escalate emergencies per Section 3.4/3.5**, with no self-care alternative offered first.
8. **Never provide specific numeric diet, calorie, or exercise-volume targets to a user with an active disordered-eating flag** (Section 5.28); this suppression persists for the remainder of the conversation once triggered, even if a later message appears unrelated.
9. **Never supply psychological narratives** attributing a user's eating pattern, mood, or behavior to an unstated cause (e.g., a relationship, trauma, or life event the user has not themselves named).
10. **Never reframe an ambiguous risk signal as benign** to shorten the conversation or reduce friction; ambiguity defaults to the more conservative risk tier (P6).
11. **Never end a conversation or reduce engagement with a user expressing self-harm risk**; continue supportively per Section 5.29.3 regardless of prior turns.
12. **Never allow the AI Composer to introduce clinical content that did not originate in a fired rule** — this is enforced by a post-generation compliance check that diffs composer output against the permitted-content set from the explainability payload (Section 7.4) before the response is released to the user.

---

## 11. Edge Cases

| Edge Case | Handling |
|---|---|
| **Multiple simultaneous symptoms** | Classify all present intents (Section 2.4); process by descending risk; if any RED-eligible combination exists (e.g., nausea + severe abdominal pain), the combination rule (e.g., SE.NAUSEA.3) takes precedence over any single-symptom GREEN rule. |
| **Contradictory information** (e.g., user says "I'm fine" but describes RED-level symptoms) | Rule content, not self-assessment framing, governs risk tier; if a user downplays symptoms that match a RED pattern, the engine still escalates and explains why, gently. |
| **Incomplete information** | Ask the minimum necessary Missing-Information questions (Section 5, per-protocol); if the user cannot/will not provide them and risk cannot be ruled out, default to the more conservative tier (P6) rather than looping indefinitely on questions. |
| **Medication not recognized** (unlisted product, compounded version, unclear name) | Do not guess dosing/timing rules for an unrecognized product; ask the user to confirm exact product name/label; if it is a known compounded/unregulated product, apply MED.INSURANCE.2 caution messaging in parallel. |
| **Unknown dosage** | Ask directly; do not assume a "typical" dose, since dosing rules are dose- and product-specific (especially missed-dose/titration logic). |
| **Missing patient profile** (new/anonymous user) | Engine still applies risk classification and RED/YELLOW protocols using only what the user states in-message; personalization layer is skipped entirely; the response includes a prompt to complete profile setup for future personalization, without blocking safety-relevant guidance. |
| **Repeated questions** (user asks the same thing again) | Detect via `conversation.recent_summary`; do not simply repeat verbatim — check whether anything changed (new symptom, time elapsed) before re-answering; if truly repeated with no new info, gently reference the prior answer and ask what's changed. |
| **Repeated unresolved symptoms** (symptom keeps recurring across memory records without resolution) | Treat as a pattern-level signal even if each individual episode looks GREEN/YELLOW; escalate the risk tier for a repeated-unresolved pattern (e.g., recurring nausea every week for 6 weeks) and recommend prescriber evaluation of the pattern itself, not just the latest episode. |
| **Long symptom duration** | Any symptom protocol's "persistent beyond X" threshold (Section 5) auto-escalates tier regardless of individual-episode severity. |
| **Travel across time zones** | Dosing is weekly-interval-based, not clock-time-based (Section 5.7/5.5); reassure the user that shifting a few hours across time zones does not require special action as long as the minimum inter-dose interval is maintained. |
| **Pregnancy concerns** | Always routes through CLIN.PREGNANCY (Section 5.32) at YELLOW minimum, RED if currently pregnant and on active therapy; never handled as a routine side-effect question even if framed that way by the user. |
| **Hypoglycemia** (in insulin/sulfonylurea users) | Cross-cutting modifier applied across SE.NAUSEA, SE.VOMITING, SE.DIZZINESS, SE.FATIGUE, LIFE.EXERCISE whenever `contraindications.known` includes insulin/sulfonylurea use and reduced intake or measured low glucose is reported; altered mental status is always RED regardless of originating intent. |
| **Medication shortages** | Route to MED.INSURANCE.3; never suggest a self-selected substitute product, off-label stretching of dosing intervals, or compounded alternative as an app-issued recommendation — this is a prescriber/pharmacy conversation. |
| **Medication switching** (e.g., semaglutide to tirzepatide or vice versa) | Treat as a prescriber-directed clinical decision; the engine may provide general education that switching protocols exist and involve dose-equivalence considerations, but never recommends a specific switch or equivalent starting dose itself. |

---

## 12. State Machine

### 12.1 Conversation State Flow

```
[New Message]
      |
      v
[Safety Pre-Filter] --match--> [RED Protocol: CLIN.EMERGENCY] --> [Response] --> [Memory Update] --> [Follow-up Scheduled]
      | no match
      v
[Intent Classification] --low confidence--> [Disambiguation Question] --> (await reply) --> back to Intent Classification
      | confident
      v
[Risk Classification] (initial pass, pre-info-collection)
      |
      v
[Patient Context Retrieval]
      |
      v
[Missing Information Collection] --incomplete & risk indeterminate--> [Ask Required Questions] --> (await reply) --> back to Risk Classification
      | sufficient
      v
[Risk Classification] (final pass, informed)
      |
      v
[Decision Engine: Rule Evaluation] --> [Rules Fired + Escalation Determination]
      |
      v
[Personalization Layer]
      |
      v
[AI Composer] --> [Compliance Diff Check] --fail--> [Fallback Safe Response] --> [Response]
      | pass
      v
[Response Delivered]
      |
      v
[Memory Update]
      |
      v
[Follow-up Scheduled] (per Section 9)
      |
      v
[Resolved | Monitoring | Escalated] (terminal/ongoing state per resolution_status)
```

### 12.2 State Invariants

- A conversation can only reach the `Decision Engine` state after risk classification has run at least once; it is never skipped.
- `Escalated` states (YELLOW-to-provider, RED-to-emergency) can only be closed by an explicit resolution event (user confirmation, provider confirmation via integration, or protocol-defined timeout-to-passive-prompt), never by silent expiry.
- `AI Composer` output is never delivered without passing the Compliance Diff Check (Section 7.4/10.12); a failed check always routes to a pre-approved static fallback message plus a logged incident for review, never a retried freeform generation without the check.

---

## 13. Protocol Versioning

### 13.1 Required Metadata Per Protocol/Rule Set

| Field | Description |
|---|---|
| `protocol_id` | Stable identifier (e.g., `SE.NAUSEA`) |
| `version` | Semantic version (MAJOR.MINOR.PATCH) |
| `last_updated` | ISO8601 date |
| `evidence_source` | Citation(s) backing each rule (FDA label version/date, guideline, study) |
| `owner` | Named clinical lead accountable for the protocol |
| `change_log` | Append-only list of {version, date, author, summary, evidence_diff} |
| `deprecation_policy` | Conditions under which a rule/protocol version is retired (e.g., FDA label update supersedes prior missed-dose window) |

### 13.2 Versioning Rules

- **MAJOR** version bump: any change that alters risk-tier outcomes or escalation behavior for existing rule conditions.
- **MINOR** version bump: new rule added, or new intent/protocol added, without changing existing behavior.
- **PATCH** version bump: wording/clarity changes to `RECOMMEND` text that do not change clinical substance, tier, or conditions.
- Any change tied to an FDA label update (e.g., a revised missed-dose window, new boxed warning, new contraindication) is **MAJOR**, requires clinical-lead sign-off before deployment, and must reference the specific label revision/date in `evidence_source`.
- Deprecated protocol versions remain queryable in the audit log indefinitely, even after a newer version is live, so historical responses remain explainable (P8, P10).
- No rule change ships to production without passing the full regression test suite (Section 14) for its protocol and all protocols that reference it via cross-routing.

---

## 14. Testing

### 14.1 Required Coverage Per Protocol

Every protocol in Section 5 requires, at minimum:

| Test Class | Description | Example (SE.VOMITING) |
|---|---|---|
| **Happy path** | Typical GREEN/expected-tier case | Isolated 1-episode vomiting, fluids tolerated, no red flags → YELLOW default, supportive guidance. |
| **Edge case** | Boundary conditions of thresholds | Exactly 24h without fluids tolerated — verify RED triggers at the boundary, not just beyond it. |
| **Failure case** | Malformed/unexpected input | User provides a non-numeric or nonsensical duration ("a while") — verify system asks a clarifying question rather than defaulting silently. |
| **Escalation case** | Confirmed RED trigger | Vomiting + dark urine + dizziness → verify RED fires, emergency-only response delivered, no self-care content leaks in. |
| **Missing information case** | Required fields absent | User reports "I'm vomiting" with no other detail → verify the minimum triage subset (fluids down? pain? fever?) is asked before any recommendation is given. |
| **Incorrect input case** | Context conflicts with message | `demographics.pregnancy_status` says "not pregnant" but user's message says "I might be pregnant" → verify the engine updates context and re-routes to CLIN.PREGNANCY rather than trusting stale context. |
| **Cross-routing case** | Verify hand-offs between protocols fire correctly | Vomiting + severe abdominal pain → verify it correctly invokes the pancreatitis RED path (SE.NAUSEA.3 logic) rather than terminating in SE.VOMITING alone. |

### 14.2 Expected Output Format for Test Assertions

Tests assert against the **explainability payload** (Section 7.4), not composer prose (which is nondeterministic in wording). A test passes if:
- `intent_primary` matches expected
- `risk_tier` matches expected
- `rules_fired` includes the expected rule ID(s) and excludes any rule ID that should not fire for that input
- `escalation_action` matches expected
- `missing_info_requested` matches expected when applicable

### 14.3 Regression Requirements

Any change to a shared cross-routing rule (e.g., the dehydration/AKI RED pattern referenced by SE.NAUSEA, SE.VOMITING, SE.DIARRHEA, SE.DIZZINESS) triggers full regression testing of every protocol that references it, not just the protocol where the change was made.

---

## 15. Evidence Sources

This specification's clinical thresholds are grounded in the following categories of source; all rule-level `SOURCE` fields must resolve to a specific, current document from one of these categories at implementation time (labels are revised periodically and the current version must always be pulled at build time, not hard-coded from this document):

1. **FDA-approved Prescribing Information / Medication Guides** for the specific product in use (semaglutide products: Wegovy, Ozempic; tirzepatide products: Zepbound, Mounjaro), including boxed warnings, contraindications (personal/family history of medullary thyroid carcinoma or MEN 2), warnings and precautions (acute pancreatitis, gallbladder disease, hypoglycemia with concomitant insulin secretagogues, hypersensitivity reactions, acute kidney injury), dosage/administration (injection sites, storage, missed-dose windows), and use-in-pregnancy sections. Sourced from accessdata.fda.gov drug label documents and manufacturer prescribing-information pages (novo-pi.com, pi.lilly.com).
2. **FDA class-wide safety communications**, including the FDA-required labeling update regarding acute kidney injury risk associated with dehydration from GLP-1-class gastrointestinal adverse reactions (nausea, vomiting, diarrhea).
3. **Peer-reviewed literature and clinical-society summaries** on GLP-1-associated pancreatitis and gallbladder/biliary disease risk (e.g., systematic reviews and meta-analyses of randomized controlled trials on gallbladder disease risk; case-report literature on pancreatitis with GLP-1/GIP therapy switching).
4. **Manufacturer patient-facing dosing and administration guidance** (missed-dose timing, injection-site rotation, storage windows) cross-checked against the primary FDA label for consistency.
5. **Established crisis-resource standards** (e.g., 988 Suicide & Crisis Lifeline in the U.S., National Alliance for Eating Disorders helpline) for mental-health and disordered-eating escalation content.

**Note to implementers:** because drug labeling is revised periodically (dosing tables, warnings, and indications can change), the engine's build/deploy pipeline should include an automated or scheduled manual check against the current FDA label for each supported product before each MAJOR protocol version release, per Section 13.2.

---

## Appendix A — Open Implementation Questions for Clinical Sign-Off

1. Exact confidence threshold for intent classification (0.72 used here as an illustrative default) should be tuned against a labeled validation set before launch.
2. Exact numeric thresholds (e.g., "5-7 days no improvement," "2.5 cm redness," "800 kcal/day") are illustrative defaults drawn from general clinical practice patterns and must be reviewed/adjusted by the clinical lead of record before production use.
3. Whether the application will support live provider-notification integration (affecting Section 3.4/9 wellness-check mechanics) or operate as a fully standalone consumer app (affecting escalation language, which would rely solely on directing the user to independently contact their own care team or emergency services).
4. Jurisdiction-specific emergency numbers/crisis resources must be localized; this document uses U.S. defaults (911, 988) as the reference implementation.

