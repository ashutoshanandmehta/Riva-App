import SwiftUI

/// Home dashboard — TPC Home v3 design.
///
/// Sections (top → bottom):
///   Brand bar + greeting · Week strip · Today card · Today's plan (habits) ·
///   Calories card · Stat tiles (next shot + weight) · Companion shortcut
struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: HomeViewModel
    private let todoRepository: any TodoRepository

    @State private var todoDone = 0
    @State private var todoTotal = 0

    init(repository: any HomeRepository, todoRepository: any TodoRepository) {
        _viewModel = State(initialValue: HomeViewModel(repository: repository))
        self.todoRepository = todoRepository
    }

    var body: some View {
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
        .background(TPCColor.background)
        .contentMargins(.bottom, TPCLayout.tabBarClearance, for: .scrollContent)
        .refreshable { await refresh() }
        .task { await refresh() }
        .onChange(of: appModel.dashboardRevision) {
            if let totals = appModel.pendingTotals {
                viewModel.apply(totals: totals)
            }
            Task { await viewModel.load() }
        }
    }

    // MARK: Loaded content

    private func content(_ snapshot: HomeSnapshot) -> some View {
        LazyVStack(spacing: TPCSpacing.md) {
            HomeHeader(
                userName: snapshot.user.firstName,
                streak: 0,
                onSettings: { appModel.showProfile() }
            )

            weekStrip

            todayCard

            todaysPlanSection

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

    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(currentWeekDays(), id: \.offset) { item in
                weekDayCell(item)
            }
        }
    }

    private func weekDayCell(_ item: WeekDayItem) -> some View {
        VStack(spacing: 6) {
            Text(item.letter)
                .font(.system(size: 9, weight: .bold))
                .kerning(0.1)
                .textCase(.uppercase)
                .foregroundStyle(item.isToday ? TPCColor.textOnInverseSecondary : TPCColor.textTertiary)

            ZStack {
                Circle()
                    .fill(item.isToday ? TPCColor.brand : TPCColor.fillNeutral)
                if item.isPast {
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
                            Text("\(todoDone)")
                                .font(TPCFont.metricXL)
                                .foregroundStyle(TPCColor.textOnInversePrimary)
                            Text("/ \(todoTotal > 0 ? "\(todoTotal)" : "–")")
                                .font(TPCFont.metricL)
                                .foregroundStyle(TPCColor.textOnInverseSecondary)
                        }
                    }

                    Spacer()

                    Button {
                        // Scroll to today's plan — companion shortcut for now
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
                        progress: todoTotal > 0 ? Double(todoDone) / Double(todoTotal) : 0,
                        height: 6,
                        tint: TPCColor.accentGold
                    )
                }
            }
        }
    }

    // MARK: Today's plan

    private var todaysPlanSection: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            HStack {
                Text("Today's plan")
                    .font(TPCFont.sectionTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Spacer()
                Button("See all") {
                    // Full todo list — wired when DetailScreen.todoList is added
                }
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(TPCColor.accentLink)
            }

            TodoSection(repository: todoRepository)
        }
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
                value: "— lbs"
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

    private func refresh() async {
        await viewModel.load()
        await loadTodoSummary()
    }

    private func loadTodoSummary() async {
        guard let todos = try? await todoRepository.todos() else { return }
        let today = Calendar.current.startOfDay(for: .now)
        let relevant = todos.filter { todo in
            switch todo.repeatRule {
            case .daily: return true
            case .once:
                guard let due = todo.dueDate else { return false }
                return due == DateFormatter.yyyyMMdd.string(from: .now)
            }
        }
        todoDone = relevant.filter(\.isDone).count
        todoTotal = relevant.count
    }

    private func nextShotLabel(_ shot: ScheduledShot) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return "\(formatter.string(from: shot.date)) · \(RivaFormat.doseMg(shot.doseMg))"
    }

    // MARK: Week strip model

    private struct WeekDayItem {
        let offset: Int
        let letter: String
        let isToday: Bool
        let isPast: Bool
    }

    private func currentWeekDays() -> [WeekDayItem] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: today) else { return [] }
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: monday) ?? monday
            return WeekDayItem(
                offset: offset,
                letter: letters[offset],
                isToday: cal.isDate(day, inSameDayAs: today),
                isPast: day < today
            )
        }
    }
}

// MARK: - DateFormatter helper

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

#Preview {
    HomeView(repository: MockHomeRepository(), todoRepository: MockTodoRepository())
        .environment(AppModel())
}
