# Riva iOS

Companion app for Riva's GLP-1 program — patients receive it with their
medication to monitor weight, medication levels, nutrition, and wellbeing.

- **Platform:** iOS 26+ (SwiftUI, Liquid Glass design language)
- **Toolchain:** Xcode 26, Swift 5 mode
- **Bundle ID:** `in.adsys.riva`

## Repository layout

- `Riva/` + `Riva.xcodeproj` — the iOS app (this README).
- `scan-service/` — the Riva Snap backend: FastAPI scan pipeline, Supabase
  integration, SQL migrations, and the mobile web tester. It has its own
  README and ARCHITECTURE docs. Note for maintainers: production deploys
  come from a mirror repo (Riva-Snap) that Render watches; sync it when
  changing `scan-service/`.

## Running

Open `Riva.xcodeproj` in Xcode and run the `Riva` target, or from the CLI:

```sh
xcodebuild -project Riva.xcodeproj -target Riva -sdk iphonesimulator -configuration Debug build
xcrun simctl install booted build/Debug-iphonesimulator/Riva.app
xcrun simctl launch booted in.adsys.riva
```

Debug launch arguments:

- `-riva.snapMenuOpen` — launches with the radial snap menu open (screenshots/UI tests).
- `-riva.tab <home|wellness|medication|tracker>` — launches on a specific tab.
- `-riva.trackerRoute weeklySummary` — launches with Weekly Summary pushed.
- `-riva.profile` — launches with the profile screen presented.
- `-riva.scan <auto|food|water>` — launches straight into the snap scan flow.
- `-riva.scanService <url>` — points the scanner at a local scan service.
- `-riva.accessToken <jwt> -riva.refreshToken <t>` — injects a session (skips sign-in).
- `-riva.scanTestImage <path>` — auto-scans a photo from disk on entry;
  add `-riva.scanAutoAccept YES` to also log it. Together these drive the
  whole scan pipeline end to end without touching the UI.

## Architecture

```
Riva/
├── App/            App entry, composition root, app-level chrome
│   ├── RivaApp.swift          @main; wires AppModel + AppDependencies
│   ├── AppDependencies.swift  Composition root — ALL repositories built here
│   ├── AppModel.swift         App-wide UI state (tab, snap menu, placeholder sheets)
│   ├── RootView.swift         Tab content + scrim + fan + tab bar + sheets
│   └── RivaTabBar.swift       Liquid Glass bottom bar with central snap button
├── DesignSystem/
│   ├── Foundation/            Tokens: RivaColor, RivaFont, RivaSpacing/Radius/Layout/Shadow
│   └── Components/            RivaCard, RivaBadge, RivaIconChip, RivaStatTile,
│                              RivaProgressBar, RivaProgressRing, RivaButtons
├── Core/
│   ├── Models/                Pure domain models (Sendable value types)
│   ├── Repositories/          Home / Medication / Wellness / Profile protocols + mocks
│   ├── Support/               RivaFormat, AttributedString.rivaHighlighted
│   └── Navigation/            AppTab, SnapAction
├── Features/
│   ├── Home/                  HomeView + HomeViewModel + card components
│   ├── Medication/            MedicationView + MedicationViewModel + components
│   ├── Tracker/               Dashboard + WeeklySummary/ (NavigationStack push)
│   ├── Profile/               Settings screen (slide-over from the gear button)
│   ├── Wellness/              Placeholder tab
│   └── Snap/                  SnapRadialFan (radial quick-log menu)
└── Shared/                    BrandTopBar, StatusViews, PlaceholderScreen/Sheet
```

### Layering rules

1. **DesignSystem** knows nothing about features or models. Feature UIs are
   composed from its tokens and components — never raw hex colors, font sizes,
   or magic paddings in feature code.
2. **Core** (models + repositories) knows nothing about SwiftUI. Repositories
   are protocols; views depend on the protocol, never a concrete type.
3. **Features** own their screens and view models. A feature receives its
   repositories through its initializer (injected from `AppDependencies`).
4. **App** is the only layer that knows about everything — it composes
   dependencies and chrome.

### Adding a feature (checklist)

1. Model(s) in `Core/Models`, repository protocol in `Core/Repositories`,
   mock implementation alongside it.
2. Register the repository in `AppDependencies`.
3. Create `Features/<Name>/` with `<Name>View` + `<Name>ViewModel`
   (`@MainActor @Observable`, state enum: `loading / loaded / failed`).
4. Reuse DesignSystem components; add new ones there if they're generic.
5. Replace the relevant `PlaceholderContext` / `PlaceholderScreen` usage.

### Swapping mock data for the real backend

Implement `APIHomeRepository: HomeRepository` and change one line in
`AppDependencies.live()`. Views and view models are untouched.

## Current status

**Live features.** Sign-in and the food scanner are real:

- The app gates on a single sign-in at launch (Supabase email code via
  `AuthModel` + `SupabaseAuthRepository`; session persists in the Keychain).
  The landing screen layout is provisional pending the final design.
- Snap → Food / Water opens the scan flow (`Features/Snap/Scan`): camera or
  photo library, mode chips, vision scan through the deployed scan service,
  result card with USDA MATCHED badges, and Accept, which writes
  `food_entries` plus the `nutrition_days` daily totals through the
  server-authoritative `/v1/log` endpoint.

Dashboards are still **placeholder** by design: Home, Medication, Tracker
(+ Weekly Summary), and Profile render mock-repository data mirroring the
approved Figma wireframes; remaining buttons respond with the consistent
"coming soon" sheet (`PlaceholderSheet`). The Wellness tab is a placeholder
screen. The Home nutrition cards do not yet read the logged totals back;
that lands with the dashboard APIs.

Other real behavior: tab switching, snap radial menu, Tracker → Weekly
Summary (push), Weekly Summary → MANAGE → Medication tab, gear → Profile
(slide-over), and the System/Light/Dark appearance setting (persisted).

Known mock inconsistencies to reconcile with design before the real backend
lands: Home says Tirzepatide 12.5 mg / 164.2 lbs, while the Medication and
Wellness wireframes imply Semaglutide 0.5 mg / 184.2 lbs. Each screen
currently mirrors its own wireframe.

Roadmap hooks already accounted for:

- **Landing page**: replace the provisional `LandingSignInView` header with
  the branded design (flow and auth plumbing stay).
- **Snap → Weight**: quick-log sheet feeding the Home cards.
- **Dashboards on live data**: implement API-backed Home/Tracker
  repositories that read `nutrition_days`, swap them in `AppDependencies`.
- **Medication**: dose schedule, site rotation, refill, side-effect logging.
- **Compliance (pre-App Store)**: this app handles health data — plan for
  HealthKit entitlements as needed, a privacy manifest, HIPAA-aligned backend,
  and App Review's medical-app requirements (drug dosing features may require
  documentation).

## Design notes

- Liquid Glass is used for **chrome only** (tab bar, snap button, radial fan),
  per Apple guidance; content cards stay opaque.
- Inside `GlassEffectContainer`, glass views must be **removed** when hidden —
  `opacity(0)` leaves the glass layer visible (see `SnapRadialFan`).
- All colors/typography/spacing live in `DesignSystem/Foundation`; light and
  dark variants are defined for every color token.
- **Dark mode**: elevation uses shadows in light mode and a hairline
  `surfaceOutline` stroke in dark mode (shadows vanish on dark backgrounds).
  Apply `.rivaSurfaceOutline(cornerRadius:)` to any new elevated surface;
  `RivaCard` does it automatically. Never hardcode `.white`/`.black` for
  content — always use a semantic token.
- Custom brand icons are SVGs in `Assets.xcassets` (template rendering,
  vector data preserved) rendered through `RivaIcon`/`RivaIconView`, so they
  tint and scale exactly like SF Symbols. To add one: drop the SVG into a new
  imageset, then reference it as `.asset("Name")`.
