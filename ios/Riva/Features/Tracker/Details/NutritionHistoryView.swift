import SwiftUI

/// Which Tracker metric a `NutritionHistoryView` is showing.
enum NutritionMetric: Sendable {
    case calories
    case protein
    case hydration

    var title: String {
        switch self {
        case .calories: "Calorie History"
        case .protein: "Protein History"
        case .hydration: "Hydration History"
        }
    }

    var emptyImage: String {
        switch self {
        case .calories: "flame"
        case .protein: "fork.knife"
        case .hydration: "drop"
        }
    }

    var emptyMessage: String {
        switch self {
        case .calories: "No calories logged yet. Scan a meal or use the quick-add button."
        case .protein: "No protein logged yet. Scan a meal or use the quick-add button."
        case .hydration: "No water logged yet. Use the quick-add button to log a glass."
        }
    }

    /// Whether an entry contributes to this metric.
    func isRelevant(_ entry: FoodEntry) -> Bool {
        switch self {
        case .calories: entry.calories > 0
        case .protein: entry.proteinGrams > 0
        case .hydration: entry.waterOunces > 0
        }
    }

    /// The metric value shown on a row ("180 kcal" / "3 g protein" / glasses).
    func valueText(_ entry: FoodEntry) -> String {
        switch self {
        case .calories:
            return "\(entry.calories) kcal"
        case .protein:
            return "\(entry.proteinGrams) g protein"
        case .hydration:
            let glasses = entry.waterOunces / 8
            return "\(glasses) \(glasses == 1 ? "glass" : "glasses")"
        }
    }
}

/// Per-metric log history sheet for the Tracker cards: the last 7 days of
/// relevant entries grouped by day, with an option to load the full history.
struct NutritionHistoryView: View {
    let metric: NutritionMetric
    let onClose: () -> Void

    @State private var model: NutritionHistoryViewModel

    init(metric: NutritionMetric, account: any AccountRepository, onClose: @escaping () -> Void) {
        self.metric = metric
        self.onClose = onClose
        _model = State(initialValue: NutritionHistoryViewModel(metric: metric, account: account))
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailSheetHeader(title: metric.title, onClose: onClose)

            ScrollView {
                switch model.state {
                case .loading:
                    LoadingStateView(message: "Loading your history…")
                case .failed(let message):
                    ErrorStateView(message: message) {
                        Task { await model.load() }
                    }
                case .loaded(let groups):
                    if groups.isEmpty {
                        DetailEmptyState(
                            systemImage: metric.emptyImage,
                            message: metric.emptyMessage
                        )
                    } else {
                        list(groups)
                    }
                }
            }
        }
        .padding(.top, TPCSpacing.sm)
        .task { await model.load() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(TPCColor.background)
    }

    // MARK: List

    private func list(_ groups: [NutritionHistoryViewModel.DayGroup]) -> some View {
        LazyVStack(alignment: .leading, spacing: TPCSpacing.md) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: TPCSpacing.sm) {
                    Text(DetailDate.dayLabel(group.day))
                        .rivaOverline()
                    ForEach(group.entries) { entry in
                        entryCard(entry)
                    }
                }
            }

            if !model.showingFull {
                Button("Show full history") {
                    Task { await model.loadFull() }
                }
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(TPCColor.brand)
                .frame(maxWidth: .infinity)
                .padding(.top, TPCSpacing.xs)
                .disabled(model.isLoadingFull)
            }
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.top, TPCSpacing.xs)
        .padding(.bottom, TPCSpacing.xl)
    }

    private func entryCard(_ entry: FoodEntry) -> some View {
        RivaCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                    Text(entry.displayName)
                        .font(TPCFont.cardTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                    Text(Self.timeLabel(entry.createdAt))
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.textSecondary)
                }
                Spacer()
                Text(metric.valueText(entry))
                    .font(TPCFont.captionEmphasized)
                    .foregroundStyle(TPCColor.brand)
            }
        }
    }

    /// "2:02 PM" from an ISO8601 created-at timestamp.
    private static func timeLabel(_ raw: String) -> String {
        guard let date = DetailDate.parse(raw) else { return "" }
        return timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

/// Loads and groups the food-entry history for one metric.
@MainActor
@Observable
final class NutritionHistoryViewModel {

    /// A single day's entries, newest first.
    struct DayGroup: Identifiable, Equatable {
        let day: String
        let entries: [FoodEntry]
        var id: String { day }
    }

    enum State: Equatable {
        case loading
        case loaded([DayGroup])
        case failed(message: String)
    }

    private(set) var state: State = .loading
    /// True once the full history (no limit) has been loaded.
    private(set) var showingFull = false
    private(set) var isLoadingFull = false

    private let metric: NutritionMetric
    private let account: any AccountRepository

    init(metric: NutritionMetric, account: any AccountRepository) {
        self.metric = metric
        self.account = account
    }

    /// Loads the recent window (last 7 days from up to 60 entries).
    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let entries = try await account.foodEntries(limit: 60)
            state = .loaded(groups(from: entries, dayLimit: 7))
        } catch is CancellationError {
            // Sheet dismissed mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Could not load your history. Try again.")
        }
    }

    /// Re-fetches with no limit and shows every day.
    func loadFull() async {
        isLoadingFull = true
        defer { isLoadingFull = false }
        do {
            let entries = try await account.foodEntries(limit: nil)
            showingFull = true
            state = .loaded(groups(from: entries, dayLimit: nil))
        } catch is CancellationError {
            // Sheet dismissed mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Could not load your full history. Try again.")
        }
    }

    /// Filters to the metric, groups by day newest-first, and (optionally)
    /// keeps only the most recent `dayLimit` days.
    private func groups(from entries: [FoodEntry], dayLimit: Int?) -> [DayGroup] {
        let relevant = entries.filter(metric.isRelevant)
        let byDay = Dictionary(grouping: relevant, by: \.day)
        let ordered = byDay.keys.sorted(by: >)
        let days = dayLimit.map { Array(ordered.prefix($0)) } ?? ordered
        return days.map { day in
            let sorted = (byDay[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            return DayGroup(day: day, entries: sorted)
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        NutritionHistoryView(metric: .calories, account: MockAccountRepository()) {}
    }
}
