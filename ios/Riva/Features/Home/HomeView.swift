import SwiftUI

/// Home dashboard — TPC Home v3 design.
///
/// Sections (top → bottom):
///   Brand bar + greeting · Week strip · Today card · Today's plan (habits) ·
///   Calories card · Stat tiles (next shot + weight) · Companion shortcut
struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: HomeViewModel
    /// Owned here, not by `TodoSection`, so the "Knocked out today" counter and
    /// the to-do card read the same list — one fetch, and ticking a to-do moves
    /// both at once.
    @State private var todoViewModel: TodoListViewModel
    /// Set by "Let's go ›"; the reader inside the scroll view acts on it and
    /// clears it. A flag rather than a direct call because the proxy only
    /// exists inside the `ScrollViewReader`.
    @State private var scrollToPlan = false

    /// Scroll target for "Let's go ›".
    private static let planAnchor = "home.todaysPlan"

    init(repository: any HomeRepository, todoRepository: any TodoRepository) {
        _viewModel = State(initialValue: HomeViewModel(repository: repository))
        _todoViewModel = State(initialValue: TodoListViewModel(repository: todoRepository))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned: the brand bar stays put while the tab scrolls under it.
            BrandTopBar(onSettings: { appModel.showProfile() })
                .padding(.horizontal, TPCSpacing.screenMargin)
                .padding(.top, TPCSpacing.xs)

            ScrollViewReader { proxy in
                ScrollView {
                    switch viewModel.state {
                    case .loading:
                        LoadingStateView(message: "Loading your day…")
                    case .failed(let message):
                        ErrorStateView(message: message) {
                            Task { await viewModel.load() }
                        }
                    case .loaded(let snapshot):
                        content(snapshot)
                    }
                }
                .onChange(of: scrollToPlan) {
                    guard scrollToPlan else { return }
                    withAnimation { proxy.scrollTo(Self.planAnchor, anchor: .top) }
                    scrollToPlan = false
                }
            }
        }
        .background(TPCColor.background)
        .contentMargins(.bottom, TPCLayout.tabBarClearance, for: .scrollContent)
        .refreshable { await refresh() }
        .task { await refresh() }
        // A scan or quick log can also satisfy a to-do, so the card refetches
        // alongside the dashboard.
        .onChange(of: appModel.dashboardRevision) {
            if let totals = appModel.pendingTotals {
                viewModel.apply(totals: totals)
            }
            Task { await refresh() }
        }
    }

    // MARK: Loaded content

    private func content(_ snapshot: HomeSnapshot) -> some View {
        LazyVStack(spacing: TPCSpacing.md) {
            HomeHeader(userName: snapshot.user.firstName, streak: snapshot.streakDays)

            weekStrip(snapshot.week)

            todayCard

            todaysPlanSection

            // Journey progress frames the day's numbers that follow. Absent
            // until the user sets a goal weight — an invented target reads as
            // failure.
            if let goal = snapshot.goal {
                TPCCard { GoalProgressSection(goal: goal) }
            }

            CaloriesTodayCard(nutrients: snapshot.nutrients) {
                appModel.open(snapAction: .food)
            }

            statTiles(snapshot)

            companionShortcut
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.top, TPCSpacing.xs)
    }

    // MARK: Week strip

    private func weekStrip(_ days: [HomeDayStatus]) -> some View {
        HStack(spacing: 8) {
            ForEach(days) { day in
                weekDayCell(day)
            }
        }
    }

    private func weekDayCell(_ item: HomeDayStatus) -> some View {
        VStack(spacing: 6) {
            Text(item.letter)
                .font(.system(size: 9, weight: .bold))
                .kerning(0.1)
                .textCase(.uppercase)
                .foregroundStyle(item.isToday ? TPCColor.textOnInverseSecondary : TPCColor.textTertiary)

            ZStack {
                Circle()
                    .fill(item.isToday ? TPCColor.brand : TPCColor.fillNeutral)
                if item.isLogged {
                    Text("✓")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TPCColor.positive)
                } else if item.isToday {
                    Circle()
                        .fill(TPCColor.accentGold)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 22, height: 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(item.isToday ? TPCColor.brandDeep : TPCColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .tpcSurfaceOutline(cornerRadius: 16)
    }

    // MARK: Today card

    private var todayCard: some View {
        TPCCard(style: .inverse) {
            VStack(alignment: .leading, spacing: TPCSpacing.md) {
                HStack {
                    Text("Today")
                        .tpcOverline(TPCColor.accentPale.opacity(0.8))
                    Spacer()
                    Text("Pull to refresh")
                        .font(TPCFont.caption)
                        .foregroundStyle(TPCColor.textOnInverseSecondary)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Knocked out today")
                            .font(TPCFont.footnote)
                            .foregroundStyle(TPCColor.textOnInverseSecondary)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(todoViewModel.completedCount)")
                                .font(TPCFont.metricXL)
                                .foregroundStyle(TPCColor.textOnInversePrimary)
                            Text("/ \(todoTotal > 0 ? "\(todoTotal)" : "–")")
                                .font(TPCFont.metricL)
                                .foregroundStyle(TPCColor.textOnInverseSecondary)
                        }
                    }

                    Spacer()

                    Button {
                        scrollToPlan = true
                    } label: {
                        Text("Let's go ›")
                            .font(TPCFont.captionEmphasized)
                            .foregroundStyle(TPCColor.textOnBrand)
                            .padding(.horizontal, 19)
                            .padding(.vertical, 13)
                            .background(TPCColor.brand, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if todoTotal > 0 {
                    TPCProgressBar(
                        progress: Double(todoViewModel.completedCount) / Double(todoTotal),
                        height: 6,
                        tint: TPCColor.accentGold
                    )
                }
            }
        }
    }

    // MARK: Today's plan

    /// No "See all": `TodoCard` already lists every open to-do, so a second
    /// screen would show the same rows twice.
    private var todaysPlanSection: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            Text("Today's plan")
                .font(TPCFont.sectionTitle)
                .foregroundStyle(TPCColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TodoSection(viewModel: todoViewModel)
        }
        .id(Self.planAnchor)
    }

    // MARK: Stat tiles

    private func statTiles(_ snapshot: HomeSnapshot) -> some View {
        HStack(spacing: 12) {
            statTile(
                icon: "💉",
                iconBg: TPCColor.brandSoft,
                label: "Next shot",
                value: nextShotLabel(snapshot.nextShot)
            )
            statTile(
                icon: "⚖️",
                iconBg: TPCColor.fillNeutral,
                label: "Weight today",
                value: snapshot.weightTodayLbs.map { "\(RivaFormat.weight($0)) lbs" } ?? "— lbs"
            )
        }
    }

    private func statTile(icon: String, iconBg: Color, label: String, value: String) -> some View {
        TPCCard {
            VStack(alignment: .leading, spacing: 9) {
                Text(icon)
                    .font(.system(size: 15))
                    .frame(width: 34, height: 34)
                    .background(iconBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(label)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)

                Text(value)
                    .font(TPCFont.cardTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Companion shortcut

    private var companionShortcut: some View {
        Button {
            appModel.select(tab: .companion)
        } label: {
            HStack(spacing: TPCSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(TPCColor.surfaceInverse)
                    Text("✦")
                        .font(.system(size: 17))
                        .foregroundStyle(TPCColor.accentPale)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Something feel off?")
                        .font(TPCFont.cardTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                    Text("Ask the companion — it sorts it in seconds.")
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.textSecondary)
                }

                Spacer()

                Text("›")
                    .font(.system(size: 16))
                    .foregroundStyle(TPCColor.accentLink)
            }
            .padding(TPCSpacing.md)
            .background(TPCColor.brandSoft, in: RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous)
                    .strokeBorder(TPCColor.brand.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    /// The card and the counter share one to-do fetch; `TodoListViewModel`
    /// resolves "done today" server-side, so there is no day math here.
    private var todoTotal: Int { todoViewModel.todos.count }

    private func refresh() async {
        await viewModel.load()
        await todoViewModel.load()
    }

    private func nextShotLabel(_ shot: ScheduledShot) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return "\(formatter.string(from: shot.date)) · \(RivaFormat.doseMg(shot.doseMg))"
    }
}

#Preview {
    HomeView(repository: MockHomeRepository(), todoRepository: MockTodoRepository())
        .environment(AppModel())
}
