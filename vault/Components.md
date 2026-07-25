# Components

Canonical catalogue of reusable SwiftUI components. Types live under
`ios/Riva/`. Feature components are listed only where genuinely reusable; most
`Features/*/Components` views are single-screen.

## Containers & surfaces

- **`RivaCard<Content>`** — `DesignSystem/Components/RivaCard.swift`
  Standard card container (radius, padding, elevation, hairline outline). All
  dashboard modules sit inside one. Init: `RivaCard(style: Style = .standard) { content }`.
  `Style`: `.standard` (white, elevated), `.inverse` (dark surface, e.g. Next
  Shot), `.tinted` (soft brand wash, no elevation).

- **`.rivaSurfaceOutline(cornerRadius:)`** — `DesignSystem/Components/RivaSurfaceOutline.swift`
  View modifier: hairline border for elevated surfaces. Invisible in light
  mode, faint stroke in dark. Apply after the background with the same radius.

- **`RivaIconChip`** — `DesignSystem/Components/RivaIconChip.swift`
  Rounded-square icon chip for card headers/list rows.
  Init: `RivaIconChip(systemImage:, tint: = .brand, background: = .brandWash, size: CGFloat = 30)`.

## Buttons

- **`RivaPrimaryButtonStyle`** — `DesignSystem/Components/RivaButtons.swift`
  Filled brand CTA. Use as `.buttonStyle(.rivaPrimary)`.
- **`RivaDestructiveButtonStyle`** — same file.
  Soft destructive (danger text on faint fill). `.buttonStyle(.rivaDestructive)`.
- **`RivaQuickAddButton`** — `DesignSystem/Components/RivaQuickAddButton.swift`
  Floating circular "+" for one-tap logging on tiles.
  Init: `RivaQuickAddButton(accessibilityLabel: String, action: () -> Void)`.

## Cards / tiles / badges

- **`RivaBadge`** — `DesignSystem/Components/RivaBadge.swift`
  Small uppercase pill. Init: `RivaBadge(text:, style: Style = .neutral)`.
  `Style`: `.neutral`, `.brand`, `.onInverse`.
- **`RivaStatTile`** — `DesignSystem/Components/RivaStatTile.swift`
  Compact tinted single-stat tile.
  Init: `RivaStatTile(caption:, systemImage:, value:, unit:)`.
- **`SettingsRow`** — `Features/Profile/Components/SettingsRow.swift`
  Settings list row: icon chip + title + optional subtitle + chevron.
  Init: `SettingsRow(systemImage:, title:, subtitle: String?, action:)`.

## Progress / charts

- **`RivaProgressBar`** — `DesignSystem/Components/RivaProgressBar.swift`
  Slim rounded bar (progress clamped 0...1). Init: `RivaProgressBar(progress:, height: = 8, tint: = .brand, track: = .brandSoft)`.
- **`RivaProgressRing<Center>`** — `DesignSystem/Components/RivaProgressRing.swift`
  Circular ring with arbitrary center content.
  Init: `RivaProgressRing(progress:, size: = 68, lineWidth: = 6, tint:, track:) { center }`.
- **`WeightBarsStrip`** — `Features/Tracker/Components/WeightBarsStrip.swift`
  Daily-weight bar strip (tint deepens toward today); shared by Tracker
  dashboard and Weekly Summary. Init: `WeightBarsStrip(dailyLbs: [Double], barHeight: = 56)`.

## Icons

- **`RivaIcon`** (enum) + **`RivaIconView`** — `DesignSystem/Foundation/RivaIcon.swift`
  `RivaIcon` is `.symbol(String)` (SF Symbol) or `.asset(String)` (template
  image). `RivaIconView(icon:, pointSize: = 19, weight: = .regular, scale: = 1)`
  renders both uniformly, inheriting `foregroundStyle`.

## Top bars & headers

- **`BrandTopBar`** — `Shared/BrandTopBar.swift`
  Brand row atop every main tab: logo + "Riva" wordmark, optional back chevron
  and settings gear. Init: `BrandTopBar(onBack: (() -> Void)? = nil, onSettings: (() -> Void)?)`.
  Used by Home (via `HomeHeader`), Tracker, Medication, Profile, Weekly Summary.
- **`DetailSheetHeader`** — `Features/Medication/Details/DetailSheetSupport.swift`
  Title + round close button for history/info sheets.
  Init: `DetailSheetHeader(title:, onClose:)`.

## Status / empty states

- **`LoadingStateView`** — `Shared/StatusViews.swift`
  In-scroll spinner + message. Init: `LoadingStateView(message: = "Loading…")`.
- **`ErrorStateView`** — `Shared/StatusViews.swift`
  In-scroll error + retry. Init: `ErrorStateView(message:, onRetry:)`.
- **`DetailEmptyState`** — `Features/Medication/Details/DetailSheetSupport.swift`
  Centered empty state for history sheets. Init: `DetailEmptyState(systemImage:, message:)`.

## Placeholders / sheets

- **`PlaceholderScreen`** — `Shared/PlaceholderScreen.swift`
  Full-screen "coming soon" tab placeholder.
  Init: `PlaceholderScreen(title:, icon: RivaIcon, iconScale: = 1, blurb:)`.
- **`PlaceholderSheet`** — `Shared/PlaceholderSheet.swift`
  Standard "coming soon" sheet (medium detent). Init: `PlaceholderSheet(context: PlaceholderContext)`.
  `PlaceholderContext` (in `App/AppModel.swift`) carries `id/title/systemImage/message`
  and ships statics (`.logShot`, `.logProtein`, …) plus `init(for: SnapAction)`.

## App chrome (canonical, not general-purpose)

- **`RivaTabBar`** — `App/RivaTabBar.swift` — floating Liquid Glass bar: four
  tabs + central snap (aperture) button. Reads `AppModel` from environment.
- **`SnapRadialFan`** — `Features/Snap/SnapRadialFan.swift` — radial Weight/
  Water/Food/3D-scan-(beta) quick-log fan; the 3D scan spoke is hidden when
  `CaptureCapability.isSupported` is false. Init: `SnapRadialFan(isOpen: Bool, onSelect: (SnapAction) -> Void)`.

---

**Rule:** Before writing a new UI component, check this file; reuse or extend
an existing one rather than writing a one-off.
