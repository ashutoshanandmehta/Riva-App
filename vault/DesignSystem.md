# DesignSystem

Canonical design tokens for the Riva iOS app. Everything lives in
`ios/Riva/DesignSystem/Foundation/`. Feature code must go through these tokens —
never raw hex, `Color(red:green:blue:)`, or ad-hoc `Font.system(size:)`.

## Color — `RivaColor` (`Foundation/RivaColor.swift`)

Semantic `enum` of `static let Color`s, each named for role and carrying a
light + dark variant via the internal `Color(light: UInt32, dark: UInt32)`
initializer (dynamic `UIColor` on trait `.userInterfaceStyle`).

- Brand: `brand` (teal), `brandDeep` (filled buttons / snap aperture),
  `brandSoft` (bar/ring tracks), `brandWash` (tinted tiles, chips).
- Landing hero gradient: `heroTop`, `heroMid`, `heroBottom`.
- Surfaces: `background` (app bg), `surface` (card), `surfaceInverse`
  (dark card, e.g. Next Shot), `fillNeutral` (neutral chip), `surfaceOutline`
  (hairline; clear in light, faint white in dark).
- Content: `textPrimary`, `textSecondary`, `textTertiary`, `textOnBrand`,
  `textOnInversePrimary`, `textOnInverseSecondary`.
- On-inverse accents: `brandOnInverse`, `fillOnInverse`.
- Feedback: `positive`, `warning`, `danger`.

## Typography — `RivaFont` (`Foundation/RivaTypography.swift`)

`enum` of `static let Font`. Scale: `screenTitle` (26 bold), `sectionTitle`
(19 bold), `cardTitle` (16 semibold), `cardHero` (22 bold), `metricXL` (32),
`metricM` (18), `metricUnit` (14), `body` (15), `footnote` (13),
`captionEmphasized` (13 semibold), `overline` (10.5 semibold), `tabLabel`
(10.5 medium).

Overline labels (small uppercase caption/badge text) are applied via the
modifier **`.rivaOverline(_ color: Color = .textSecondary)`** — sets font,
uppercase casing, and 0.8 kerning uniformly. Prefer it over styling text
manually.

## Spacing — `RivaSpacing` (`Foundation/RivaMetrics.swift`)

`xxs 4, xs 8, sm 12, md 16, lg 20, xl 24, xxl 32`. `screenMargin = 20` is the
standard horizontal screen inset.

## Corner radii — `RivaRadius` (same file)

`card 24`, `tile 16` (nested inside cards), `control 18` (buttons). Always use
`RoundedRectangle(cornerRadius:, style: .continuous)`.

## Layout — `RivaLayout` (same file)

App chrome constants: `tabBarHeight 64`, `tabBarClearance 108` (bottom scroll
inset so content clears the floating tab bar), `snapButtonSize 58`,
`snapActionSize 56`, `snapFanRadius 96`.

## Elevation — `RivaShadow` (same file)

`RivaShadow.card(view)` — soft resting card shadow (opacity 0.06, r14, y6).
`RivaShadow.floating(view)` — stronger, for floating elements (opacity 0.12,
r16, y8). Note: shadows are invisible in dark mode, where `surfaceOutline` /
`.rivaSurfaceOutline` supplies separation instead.

## Materials — "Liquid Glass"

The floating tab bar and snap buttons use the system glass APIs (iOS 26):
- `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, ...))` on the
  tab bar (`App/RivaTabBar.swift`).
- `.glassEffect(.regular.tint(RivaColor.brandDeep).interactive(), in: Circle())`
  on the snap aperture button.
- `.glassEffect(.regular.interactive(), in: Circle())` on fan buttons, wrapped
  in a `GlassEffectContainer(spacing: 24)` (`Features/Snap/SnapRadialFan.swift`)
  so glass shapes blend fluidly while animating. Note: buttons inside a glass
  container must be removed (not just hidden) when inactive.

Cards do NOT use glass — they use solid `RivaColor.surface` + shadow + outline.
Glass is reserved for floating app chrome.

## Composing a new screen

1. Root is a `ScrollView` with `.background(RivaColor.background)` and
   `.contentMargins(.bottom, RivaLayout.tabBarClearance, for: .scrollContent)`
   so content clears the tab bar (see `Features/Home/HomeView.swift`).
2. Content in a `LazyVStack(spacing: RivaSpacing.md)`, padded
   `.horizontal, RivaSpacing.screenMargin`.
3. Start with `BrandTopBar` (directly or via a feature header like
   `HomeHeader`); pass `onSettings: { appModel.showProfile() }`, and `onBack`
   for pushed sub-screens.
4. Wrap each module in `RivaCard`. Use `LoadingStateView` / `ErrorStateView`
   for async states.
5. Tabs are defined by the `AppTab` enum (`Core/Navigation/AppTab.swift`:
   `home, wellness, medication, tracker`, split `leading`/`trailing` around the
   snap button). `RootView` (`App/RootView.swift`) hosts all tabs mounted at
   once, the `RivaTabBar`, the `SnapRadialFan`, and the shared sheets, driven by
   `AppModel` (`selectedTab`, `activeQuickLog`, `activeDetail`, `activeScanMode`,
   `activePlaceholder`, `isProfilePresented`). Navigation goes through `AppModel`
   methods (`select(tab:)`, `showProfile()`, `open(snapAction:)`), not ad-hoc
   `NavigationLink`s.
