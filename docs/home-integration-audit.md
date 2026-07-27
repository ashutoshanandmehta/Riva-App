# Home screen — database integration audit

_Audited 2026-07-27 on `feature/chat-companion`. Scope: everything rendered by
`ios/Riva/Features/Home/`._

> **Status 2026-07-27:** G1, G2, G3, G4, G7, and G9 are **implemented** (see
> "Implemented" at the bottom). G6 and G8 remain open. **G5 is closed as
> won't-do** — the owner chose to keep the calorie goal hardcoded at 2000 kcal
> rather than add the column, so `DashboardMapping.calorieGoalKcal` stays.

## Verdict

The **data layer is correctly wired**. The **view layer is not**. `HomeView` was
redesigned to "TPC Home v3" and several of its new surfaces were built as static
mockup markup that was never connected to the snapshot the repository already
fetches. Two of them (week strip ✓ marks, "Weight today") display *invented*
adherence/health data, which is worse than an empty state.

### Confirmed working

| Surface | Path |
|---|---|
| Repository selection | `AppDependencies.swift:40` → `APIHomeRepository`, not the mock |
| Aggregate fetch | `APIDashboardRepositories.swift:52` `GET /v1/dashboard`, bearer token, 401 → `signInRequired` |
| Backend aggregate | `backend/app/main.py:416` → `backend.get_dashboard()` (`backend.py:727`), RLS-scoped service-role reads |
| Calories card | `snapshot.nutrients` ← `nutrition_days.today` + `nutrition_goals` (`APIDashboardRepositories.swift:253-274`) |
| "Next shot" tile | `DashboardMapping.nextShot` ← `medication_plans` + `shots` |
| Loading / error / pull-to-refresh | `HomeViewModel.load()`, `HomeView.swift:22-41` |
| Optimistic post-log update | `AppModel.applyLoggedTotals` → `dashboardRevision` → `HomeViewModel.apply(totals:)` |
| To-do card itself | `TodoSection` → `APITodoRepository` → `/v1/todos` (real reads *and* writes) |

---

## Gaps

### G1 — "Weight today" tile is hardcoded `"— lbs"` — **fabricated empty state**

`HomeView.swift:203`. The value is a literal string; the user's weight never
appears on Home even when logged today.

Cause: when weight moved to the Tracker tab, `HomeSnapshot` dropped its weight
field (`HomeSnapshot.swift:8-9` comment), but the v3 tile that needs it was added
afterwards.

**Where to fix**
1. `Core/Models/HomeSnapshot.swift` — add `var weightTodayLbs: Double?`.
2. `Core/Repositories/APIDashboardRepositories.swift` (`APIHomeRepository.homeSnapshot`) —
   fill from `payload.weights.first` **only if** `measuredAt` falls on today in
   `payload.profile.timezone`; otherwise nil. (`payload.weights` is newest-first,
   90 days, already in the response — no backend change needed.)
3. `Features/Home/HomeView.swift:196-206` — render `RivaFormat.weight(...)` or
   `"— lbs"` when nil.
4. `MockHomeRepository` + previews — add the field.

### G2 — Streak chip is hardcoded `0`, so it never renders

`HomeView.swift:52` passes `streak: 0`; `HomeHeader.swift:23` hides the chip when
`streak == 0`. Dead UI.

**Where to fix** — decide the semantic first:
- *Wellness streak* (cheapest, data already present): `payload.wellness.streakDays`,
  mapped in `DashboardMapping.wellnessSummary`. Add `var streakDays: Int` to
  `HomeSnapshot`, set it in `APIHomeRepository`, pass at `HomeView.swift:52`.
- *Logging streak* (what a "🔥 Nd" chip usually means): must be computed from
  consecutive `nutrition_days` rows. `get_dashboard` only returns **7 days**
  (`backend.py:734` `week_ago`), so a client-side streak caps at 7. A real streak
  needs a backend change — either widen the window or return a `streak_days`
  integer from `backend/app/backend.py:get_dashboard`.

### G3 — Week strip shows a green ✓ on every past day regardless of activity — **fabricated adherence**

`HomeView.swift:88-113`. `isPast` is pure calendar math (`day < today`), and
`isPast` renders "✓". Monday always looks completed on a Friday, on a brand-new
account with zero logs.

**Where to fix**
1. `Core/Models/HomeSnapshot.swift` — add `var week: [HomeDayStatus]`
   (`{ date: Date, isLogged: Bool }`), or reuse a small new model in
   `Core/Models/`.
2. `APIHomeRepository.homeSnapshot` — derive from `payload.weekNutrition`
   (`DayTotals.day` is `yyyy-MM-dd`; treat `calories > 0 || waterOunces > 0` as
   logged). Consider a shared `DashboardMapping.weekActivity(_:)` so Tracker can
   reuse it.
3. `HomeView.swift:76-113` — drive `WeekDayItem.isPast` → `isLogged` from the
   snapshot; past-but-unlogged renders the neutral circle, not a ✓.

### G4 — "Knocked out today" counter double-fetches `/v1/todos` and goes stale on toggle

- `HomeView.loadTodoSummary()` (`HomeView.swift:263-278`) fetches `/v1/todos` and
  keeps its own `todoDone`/`todoTotal`.
- `TodoSection` (mounted right below it) constructs its *own* `TodoListViewModel`
  and fetches `/v1/todos` again. **Two requests per Home load.**
- Checking a to-do in `TodoSection` mutates only that view model
  (`TodoListViewModel.toggle`, which never touches `AppModel`), so
  `dashboardRevision` is not bumped and the counter + progress bar on the card
  above **do not move** until pull-to-refresh.
- `loadTodoSummary` also re-implements day math the server already did
  (`Todo.isDone` is resolved in the profile timezone server-side per
  `TodoModels.swift:57-59`), using a `DateFormatter` with no POSIX locale or
  timezone pinned (`HomeView.swift:330-336`).

**Where to fix** — single source of truth:
1. `Features/Home/HomeView.swift` — own one `@State private var todoViewModel =
   TodoListViewModel(repository: todoRepository)`; read counts from it
   (`todos.count`, `remainingCount` already exist on the view model).
2. `Features/Todos/TodoSection.swift:12-14` — accept an injected
   `TodoListViewModel` instead of constructing one; keep the current initializer
   as a preview convenience if desired.
3. Delete `loadTodoSummary()` and the private `DateFormatter.yyyyMMdd`
   extension; drop the client-side `repeatRule`/`dueDate` filter entirely.

### G5 — Calorie goal is a hardcoded 2000 kcal, not the user's goal

`DashboardMapping.calorieGoalKcal = 2000` (`APIDashboardRepositories.swift:100`)
feeds Home's ring, its "LEFT" number, and Tracker. `nutrition_goals` has
`protein_goal / carb_goal / fiber_goal / water_goal` — **no calorie column**
(`backend/supabase/migrations/0001_nutrition.sql:108`).

**Where to fix** (spans DB → backend → iOS; needs migration approval):
1. New migration `backend/supabase/migrations/0005_calorie_goal.sql` — add
   `nutrition_goals.calorie_goal integer NOT NULL DEFAULT 2000 CHECK (> 0)`.
2. `backend/app/backend.py` — add to `_GOAL_COLUMNS`, keep `_GOAL_COLUMNS_LEGACY`
   fallback (same degrade pattern already used for `wellness_minutes_goal`,
   `backend.py:386-397`).
3. `backend/app/schemas.py` — add to the goals request/response models;
   `main.py:435` `/v1/goals` accepts it.
4. `ios/.../Core/Models/AccountModels.swift:18` — `let calorieGoal: Int?`
   (optional, so older backends decode).
5. Replace every `DashboardMapping.calorieGoalKcal` use with
   `goals.calorieGoal ?? 2000` — `APIHomeRepository` and `APITrackerRepository`.
6. `Features/Profile/EditGoalsSheet` — expose the field.

### G6 — Snapshot fields computed but never rendered (wasted work / stale contract)

- `snapshot.quote` — hardcoded string literal in `APIHomeRepository:243`, not
  from the DB, and **not rendered anywhere** in Home v3.
- `snapshot.medicationLevel` — a real computation
  (`DashboardMapping.medicationLevel`, exponential decay over `shots`) that Home
  v3 no longer displays; `MedicationLevelCard` is referenced only by its own
  `#Preview`. The Medication tab computes its own curve independently.

**Where to fix** — either restore the cards or remove the fields from
`HomeSnapshot.swift`, `APIHomeRepository`, and `MockHomeRepository`. Removing is
the honest option; `MedicationLevelCard.swift` then becomes an unused component
(keep it catalogued in `vault/Components.md` or delete it deliberately).

### G7 — Two dead buttons on Home

- `"Let's go ›"` (`HomeView.swift:135`) — empty closure with a TODO comment.
- `"See all"` (`HomeView.swift:174`) — empty closure, "wired when
  `DetailScreen.todoList` is added".

**Where to fix** — `Core/Navigation/` `DetailScreen` needs a `.todoList` case
routed in `RootView.swift`, or both should use the existing
`AppModel.present(placeholder:)` path so a tap isn't dead silence.

### G8 — `/v1/dashboard` fan-out: ~6 identical round trips per write

`DashboardService.fetch()` has no caching or in-flight dedup, and Home,
Wellness, Tracker, and Medication are all mounted simultaneously and all observe
`dashboardRevision`. `APITrackerRepository` calls `fetch()` **twice**
(`trackerDashboard` + `weeklySummary`). One accepted scan therefore triggers
roughly six full aggregate fetches, each of which runs ~7 PostgREST selects
server-side.

**Where to fix** — `Core/Repositories/APIDashboardRepositories.swift`: make
`DashboardService` an `actor` holding `(payload, fetchedAt, inFlightTask)`; serve
a cached payload within a short TTL (~2 s) and coalesce concurrent callers into
one `Task`. `AppModel.refreshDashboards()` should be able to invalidate it
explicitly so a write is never served a stale cache. No call-site changes.

### G9 — Unrelated but adjacent: dead mock still in the composition root

`AppDependencies.swift:43` wires `profileRepository: MockProfileRepository()`.
Nothing reads `profileRepository` — every profile screen takes
`dependencies.accountRepository` (`RootView.swift:17,91,113…`). Safe to delete
`profileRepository`, `ProfileRepository.swift`, and `MockProfileRepository.swift`.
Flagged only so it isn't mistaken for "Home reads mock data".

---

## Suggested sequencing

| Order | Item | Blast radius | Needs approval |
|---|---|---|---|
| 1 | G3 week strip, G1 weight tile | Home only + `HomeSnapshot` | no |
| 2 | G4 to-do single source of truth | Home + `TodoSection` | no |
| 3 | G2 streak (wellness variant) | Home only | no |
| 4 | G6 remove/restore dead fields, G7 dead buttons | Home, navigation | no |
| 5 | G8 dashboard cache | all four dashboard tabs | no |
| 6 | G5 calorie goal | migration + backend + iOS + goals sheet | **yes — migration** |
| 7 | G9 delete dead mock | composition root | no (file deletion — confirm) |

Steps 1–5 are view/mapping work with no schema or endpoint change. Step 6 is the
only item that touches the database contract.

---

## Implemented — 2026-07-27 (G1, G3, G4)

No schema, endpoint, or payload change: all three were satisfied by data
`/v1/dashboard` and `/v1/todos` already return.

**G1 — weight today**
- `Core/Models/HomeSnapshot.swift` — `weightTodayLbs: Double?`.
- `DashboardMapping.weightToday(_:now:)` — latest `weights` entry whose
  `measured_at` falls on today **in the profile timezone**; nil otherwise, so an
  earlier day never stands in for today.
- `HomeView` stat tile renders `RivaFormat.weight` or `"— lbs"` when nil.

**G3 — week strip**
- `HomeDayStatus { dayKey, letter, isToday, isLogged }` in `HomeSnapshot.swift`.
- `DashboardMapping.weekActivity(_:now:)` — Monday→Sunday in the profile
  timezone; `isLogged` comes from `week_nutrition` (`calories > 0 ||
  water_ounces > 0`), never from `day < today`.
- `HomeView.weekDayCell` renders the ✓ on `isLogged`. The view's own
  `currentWeekDays()` / `WeekDayItem` and its unpinned `DateFormatter` are
  deleted — day math now lives only in the mapping layer.
- `HomeViewModel.apply(totals:)` also ticks today's cell optimistically, so it
  moves with the nutrient tiles instead of lagging until the refetch.

**G4 — one to-do fetch, one source of truth**
- `HomeView` owns the `TodoListViewModel`; `TodoSection.init(viewModel:)` now
  takes it injected instead of constructing its own.
- `TodoListViewModel.completedCount` backs "Knocked out today". Ticking a to-do
  updates the counter and progress bar in the same frame as the card.
- `HomeView.loadTodoSummary()` and its client-side `repeatRule`/`dueDate` filter
  are gone — `list_todos` already resolves `is_done` against the profile day.
- `HomeView` drives loading (`.task`, `.refreshable`, `dashboardRevision`);
  `TodoSection` keeps only the `scenePhase` reload for the local-midnight reset.
  One `/v1/todos` request per refresh instead of two.

**Behaviour change worth knowing:** the counter's denominator is now the list the
card actually shows, which `list_todos` defines — daily to-dos plus one-offs that
are due or overdue, including one-offs dated later this week. The old
client-side filter counted only today's, and silently dropped overdue one-offs.

**Verification:** `xcodebuild` clean build succeeded (iPhone 17 simulator,
Debug). **Not yet verified against live data** — the production Supabase read
and the simulator run were both blocked by the permission classifier, so the
week strip, weight tile, and to-do counter have not been observed rendering real
rows. Worth one pass on a signed-in device before this is called done.

## Implemented — 2026-07-27 (G7, G9)

**G7 — dead buttons**
- `"Let's go ›"` now scrolls to the to-do section. `HomeView` wraps its scroll
  view in a `ScrollViewReader`; the button sets a `scrollToPlan` flag that the
  reader acts on and clears (the proxy only exists inside the reader), and
  `todaysPlanSection` carries the `home.todaysPlan` anchor id.
- `"See all"` is **removed** rather than wired. `TodoCard` already renders every
  open to-do, ungrouped by nothing and untruncated, so the destination would
  have duplicated the card directly above it. Owner decision, 2026-07-27.
  - If a to-do screen is wanted later, the content that would justify it is
    *history* — one-offs completed on an earlier day, which `list_todos`
    deliberately filters out (`0004_todos.sql:88-90`). That needs a backend
    change (an include-completed flag or a separate RPC), not just a new view.

**G9 — dead composition-root wiring**
- Deleted `Core/Repositories/ProfileRepository.swift` and
  `MockProfileRepository.swift`, and dropped `profileRepository` from
  `AppDependencies`. Nothing read it; every profile screen takes
  `accountRepository`. The Xcode project uses synchronized buildable folders, so
  no `project.pbxproj` edit was needed.

**Newly orphaned by G9 — not deleted:** `Core/Models/ProfileModels.swift` now
has no callers at all. `ProfileSnapshot`, `MedicationSettings`, and the
`PersonalGoals` *model* were referenced only by the two deleted files
(`PersonalGoalsSection` is a view of the same name, not a user of the model, and
`QuantityGoal` lives in `TrackerModels.swift` and is still used). Deleting it is
the obvious follow-up but was outside the approved scope of G9.

**Verification:** `xcodebuild` clean build succeeded after both changes. The
scroll behaviour of "Let's go ›" has **not** been observed running — same
simulator restriction noted above.

## Implemented — 2026-07-27 (G2)

The streak counts **consecutive days with nutrition logged** (owner decision),
not wellness minutes. New backend field; no migration.

**Backend** (`app/backend.py`)
- `nutrition_streak(logged_days, today)` — pure function. Counts back from
  today, or from yesterday when today has nothing logged yet, mirroring
  `wellness_streak` + `wellness_summary` (`0003_wellness.sql:66,148-152`): an
  unbroken streak survives until the end of the current day.
- `profile_today(profile)` — the user's local day via `ZoneInfo`, matching the
  `log_*` functions' SQL. Falls back to the server day on an unknown timezone
  rather than failing the dashboard.
- `_logged_nutrition_days` — up to 400 days of `nutrition_days`, keeping only
  rows with `calories > 0 || water_ounces > 0`. A row exists as soon as anything
  touches the day, so row existence is not evidence of a log.
- `get_dashboard` returns `streak_days`, wrapped in try/except: a garnish must
  never fail the dashboard.

**Why Python and not SQL:** `0003` puts all streak math in SQL, and matching
that convention would mean a `nutrition_streak` Postgres function — i.e. a
migration, which the owner declined for G5 in the same session. The rules are
deliberately identical, so this can move into SQL later without a behaviour
change. Two smaller consequences worth knowing: it costs one extra PostgREST
read per dashboard call, and it filters in Python rather than with a PostgREST
`or=`, which this module has never used against the live instance.

**iOS**
- `DashboardPayload.streakDays: Int?` (optional — an older backend omits it and
  Home just hides the chip), `HomeSnapshot.streakDays: Int`,
  `APIHomeRepository` maps `?? 0`, `HomeView` passes it to `HomeHeader`.
  `HomeHeader` already hid the chip at zero, so no view change was needed there.
- `HomeViewModel.apply(totals:)` extends the streak by one on the day's first
  log — exactly right given the anchor rule, since the server was counting from
  yesterday until that log landed.

**Verification:** 9 new unit tests in `tests/test_dashboard_streak.py` covering
the anchor rule, gaps, empty history, timezone day, and the empty-row filter.
Full backend suite **436 passed**; `ruff check` and `ruff format --check` clean.
iOS `xcodebuild` clean. **Still not observed against live data** — no signed-in
run, same restriction as above.

### Not fixed, found while doing G2

`get_dashboard` computes `today`/`week_ago` from `date.today()` — the *server's*
UTC day — while `nutrition_days.day` holds the user's *local* day. So
`payload.today` can resolve to the wrong row for several hours a day for users
west of UTC (a US-evening log lands on tomorrow's UTC date). G2's streak avoids
this by using `profile_today()`, but `today_row`, `side_effects_today`, and the
`week_ago` window still use the server day. Pre-existing and out of scope here —
worth its own fix.
