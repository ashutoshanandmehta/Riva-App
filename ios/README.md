# Riva iOS

The Riva iPhone app. Patients receive it with their GLP-1 medication to
track weight, shots, nutrition, and wellbeing through treatment.

- **Platform:** iOS 26+ (SwiftUI, Liquid Glass design language)
- **Toolchain:** Xcode 26, Swift 5 mode
- **Bundle ID:** `in.adsys.riva`

## Running

Open `Riva.xcodeproj` in Xcode and run the `Riva` target, or from the CLI:

```sh
xcodebuild -project Riva.xcodeproj -target Riva -sdk iphonesimulator -configuration Debug build
xcrun simctl install booted build/Debug-iphonesimulator/Riva.app
xcrun simctl launch booted in.adsys.riva
```

Debug launch arguments I use for screenshots and self tests:

- `-riva.snapMenuOpen` launches with the radial snap menu open.
- `-riva.tab <home|wellness|medication|tracker>` launches on a tab.
- `-riva.trackerRoute weeklySummary` launches with Weekly Summary pushed.
- `-riva.profile` launches with the profile screen presented.
- `-riva.scan <auto|food|water>` launches straight into the scanner.
- `-riva.quickLog <weight|shot|protein|sideEffects|sleep>` opens a quick-log sheet.
- `-riva.scanTestImage <path>` scans a photo from disk on entry (once per
  process); add `-riva.scanAutoAccept 1` to also log it.
- `-riva.scanService <url>` points the app at a local backend.
- `-riva.accessToken <jwt> -riva.refreshToken <token>` injects a session.

## Architecture

```
Riva/
├── App/            App entry, composition root, app-level chrome
│   ├── RivaApp.swift          @main; wires AppModel + AppDependencies
│   ├── AppDependencies.swift  Composition root. ALL repositories built here
│   ├── AppModel.swift         App-wide UI state (tab, snap menu, active sheets)
│   ├── RootView.swift         Tab content + scrim + fan + tab bar + sheets
│   └── RivaTabBar.swift       Liquid Glass bottom bar with central snap button
├── DesignSystem/
│   ├── Foundation/            Tokens: RivaColor, RivaFont, RivaSpacing/Radius/Layout/Shadow
│   └── Components/            RivaCard, RivaBadge, RivaIconChip, RivaStatTile,
│                              RivaProgressBar, RivaProgressRing, RivaButtons
├── Core/
│   ├── Models/                Pure domain models, including the scan and
│   │                          quick-log types mirroring the backend contract
│   ├── Repositories/          Protocols + implementations: dashboards (mock),
│   │                          ScanRepository + LogRepository (live API),
│   │                          AuthRepository (device sessions today)
│   ├── Support/               RivaFormat, BackendEnvironment, KeychainStore
│   └── Navigation/            AppTab, SnapAction
├── Features/
│   ├── Home/                  Dashboard cards
│   ├── Medication/            Dose card, curve, history
│   ├── Tracker/               Dashboard + WeeklySummary/ (NavigationStack push)
│   ├── Snap/                  Radial quick-log fan + Scan/ (the live scanner)
│   ├── QuickLog/              Weight, shot, protein, side effects, sleep sheets
│   ├── Auth/                  Email code sign-in, parked until the landing page
│   ├── Profile/               Settings screen
│   └── Wellness/              Placeholder tab
└── Shared/                    BrandTopBar, StatusViews, PlaceholderScreen/Sheet
```

### My layering rules

1. **DesignSystem** knows nothing about features or models. Feature UIs are
   composed from its tokens and components, never raw hex colors, font
   sizes, or magic paddings in feature code.
2. **Core** (models + repositories) knows nothing about SwiftUI.
   Repositories are protocols; views depend on the protocol, never a
   concrete type.
3. **Features** own their screens and view models. A feature receives its
   repositories through its initializer (injected from `AppDependencies`).
4. **App** is the only layer that knows about everything. It composes
   dependencies and chrome.

### Adding a feature (checklist)

1. Model(s) in `Core/Models`, repository protocol in `Core/Repositories`,
   mock implementation alongside it.
2. Register the repository in `AppDependencies`.
3. Create `Features/<Name>/` with `<Name>View` + `<Name>ViewModel`
   (`@MainActor @Observable`, state enum: `loading / loaded / failed`).
4. Reuse DesignSystem components; add new ones there if they are generic.
5. Replace the relevant `PlaceholderContext` / `PlaceholderScreen` usage.

## Current status

Live against the backend:

- **Snap scanner** (Food and Water from the radial menu): camera or photo
  library, one photo in, dish + portion + USDA-grounded nutrients out.
  Accept persists the meal and the day's totals.
- **Quick logging**: weight, shots, protein, side effects, sleep. Each
  sheet saves through the backend and confirms with real numbers.
- **Identity**: silent per-device accounts (`DeviceAuthRepository`). No
  sign-in screen by design for now; when I finalize the landing page, the
  swap back to the email code flow is one line in `AppDependencies` plus
  restoring the gate in `RivaApp`.

Still mock-backed: the dashboard cards (Home, Medication, Tracker, Weekly
Summary) render sample data mirroring my wireframes until the read APIs
land. That is why logged data does not appear on Home yet. Remaining
placeholders: detail screens (weight history, shot schedule, body-map side
effects), profile settings, and the Wellness tab.

Known mock inconsistency I still need to reconcile: Home says Tirzepatide
12.5 mg / 164.2 lbs while Medication and Tracker imply Semaglutide 0.5 mg /
184.2 lbs. Each screen currently mirrors its own wireframe.

Before the App Store: this app handles health data, so plan for HealthKit
entitlements as needed, a privacy manifest, a HIPAA-aligned backend, and
App Review's medical app requirements.

## Design notes

- Liquid Glass is for **chrome only** (tab bar, snap button, radial fan),
  per Apple guidance; content cards stay opaque.
- Inside `GlassEffectContainer`, glass views must be **removed** when
  hidden. `opacity(0)` leaves the glass layer visible (see `SnapRadialFan`).
- All colors, typography, and spacing live in `DesignSystem/Foundation`;
  light and dark variants are defined for every color token.
- **Dark mode**: elevation uses shadows in light mode and a hairline
  `surfaceOutline` stroke in dark mode (shadows vanish on dark
  backgrounds). Apply `.rivaSurfaceOutline(cornerRadius:)` to any new
  elevated surface; `RivaCard` does it automatically. Never hardcode
  `.white` or `.black` for content; always use a semantic token.
- Custom brand icons are SVGs in `Assets.xcassets` (template rendering,
  vector data preserved) rendered through `RivaIcon`/`RivaIconView`, so
  they tint and scale exactly like SF Symbols. To add one: drop the SVG
  into a new imageset, then reference it as `.asset("Name")`.
