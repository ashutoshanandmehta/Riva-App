import SwiftUI

/// One detected item on the scan result card, with an inline editor behind a
/// pencil. Expanding a row offers replacements for what the scan read wrongly
/// and a manual search, so a bad item is a two-tap fix rather than a new photo.
///
/// The parent owns which row is open (only one at a time) and what replacing an
/// item means; everything about fetching and presenting candidates lives here.
struct EditableScanItemRow: View {

    let item: ScanItem
    let context: FoodReplacementContext
    /// `nil` disables editing entirely — no pencil, no editor.
    let service: (any FoodReplacementService)?
    let isExpanded: Bool
    let onToggleEdit: () -> Void
    let onReplace: (FoodSuggestion) -> Void

    @State private var searchText = ""
    @State private var suggestions: [FoodSuggestion] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            summaryRow
            if isExpanded, service != nil {
                editor
            }
        }
        .task(id: isExpanded) {
            // First expand only. Re-opening a row the user already looked at
            // should not spend another call on the same question.
            guard isExpanded, suggestions.isEmpty, loadError == nil else { return }
            await load(query: nil)
        }
        // A replacement makes this a different food, so the cached candidates
        // are answers to the old question. Drop them and ask again on reopen.
        .onChange(of: item) {
            suggestions = []
            searchText = ""
            loadError = nil
        }
    }

    // MARK: Collapsed

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: TPCSpacing.sm) {
            VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                Text(item.name.capitalized)
                    .font(TPCFont.cardTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Text("\(item.portionDesc), about \(Int(item.portionGrams.rounded()))g")
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
                Text(macroSplit)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
                    .contentTransition(.numericText())
                // Plain language over jargon: "matched" only means anything if
                // you already know the numbers come from the USDA database.
                RivaBadge(
                    text: item.matched ? "USDA data" : "Our best guess",
                    style: item.matched ? .brand : .neutral
                )
            }
            Spacer(minLength: TPCSpacing.xs)
            VStack(alignment: .trailing, spacing: TPCSpacing.xxs) {
                Text("\(item.calories)")
                    .font(TPCFont.metricM)
                    .foregroundStyle(TPCColor.textPrimary)
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(TPCFont.metricUnit)
                    .foregroundStyle(TPCColor.textSecondary)
            }
            if service != nil {
                editButton
            }
        }
    }

    private var editButton: some View {
        Button(action: onToggleEdit) {
            Image(systemName: isExpanded ? "chevron.up" : "pencil")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isExpanded ? TPCColor.brand : TPCColor.textSecondary)
                // 44pt is the minimum comfortable target, and this row is tall
                // enough to absorb it without changing its height.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Stop editing \(item.name)" : "Edit \(item.name)")
    }

    // MARK: Expanded editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            Text("Editing \"\(item.name.capitalized)\"")
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(TPCColor.textSecondary)

            Text("Suggested replacements")
                .tpcOverline()

            candidates

            TPCTextField(
                label: "Search another food",
                placeholder: "Noodles, ramen, pasta…",
                text: $searchText,
                capitalization: .never,
                submitLabel: .search,
                onSubmit: { runQuery() }
            )

            // The label follows the action: with a food typed the button looks
            // it up and swaps it in, empty it just refreshes the list above.
            Button(trimmedQuery.isEmpty ? "Get new results" : "Get nutrients") { runQuery() }
                .buttonStyle(.tpcSecondary)
                .disabled(isLoading)
                // TPCSecondaryButtonStyle does not dim when disabled, so the
                // button has to fade itself (same note as the primary style).
                .opacity(isLoading ? 0.5 : 1)
        }
        .padding(TPCSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TPCColor.fillNeutral,
            in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var candidates: some View {
        if isLoading {
            HStack(spacing: TPCSpacing.xs) {
                ProgressView().controlSize(.small)
                Text("Looking for better matches…")
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
            }
            .padding(.vertical, TPCSpacing.xxs)
        } else if let loadError {
            Text(loadError)
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.danger)
        } else if suggestions.isEmpty {
            Text("No other matches yet. Search for the food you meant.")
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textSecondary)
        } else {
            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    candidateButton(suggestion)
                }
            }
        }
    }

    private func candidateButton(_ suggestion: FoodSuggestion) -> some View {
        Button {
            onReplace(suggestion)
        } label: {
            HStack(spacing: TPCSpacing.xs) {
                VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                    Text(suggestion.name.capitalized)
                        .font(TPCFont.body)
                        .foregroundStyle(TPCColor.textPrimary)
                    Text("\(suggestion.portionDesc) • about \(Int(suggestion.portionGrams.rounded()))g")
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.textSecondary)
                }
                Spacer(minLength: TPCSpacing.xs)
                if suggestion.matched {
                    RivaBadge(text: "USDA data", style: .brand)
                }
                Text("\(suggestion.calories) kcal")
                    .font(TPCFont.metricUnit)
                    .foregroundStyle(TPCColor.textSecondary)
            }
            .padding(.vertical, TPCSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Replace with \(suggestion.name), \(suggestion.calories) calories")
    }

    // MARK: Loading

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Get new results" and the search field share one action, which depends
    /// on whether the user typed anything: a typed food is looked up and
    /// applied in one step, an empty field just refreshes the suggestions.
    /// Ignored while a request is in flight, so two overlapping lookups cannot
    /// finish out of order.
    private func runQuery() {
        guard !isLoading else { return }
        let query = trimmedQuery
        Task { query.isEmpty ? await load(query: nil) : await apply(query) }
    }

    /// Prices the typed food and swaps it in. The server returns the single
    /// best result — USDA's if it has one, otherwise composed from a recipe —
    /// so there is nothing for the user to choose between.
    private func apply(_ query: String) async {
        guard let service else { return }
        isLoading = true
        loadError = nil
        do {
            if let replacement = try await service.search(query, in: context).first {
                onReplace(replacement)
            } else {
                loadError = "We could not find \"\(query)\". Try another name."
            }
        } catch {
            if !Task.isCancelled {
                loadError = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func load(query: String?) async {
        guard let service else { return }
        isLoading = true
        loadError = nil
        do {
            let results: [FoodSuggestion]
            if let query {
                results = try await service.search(query, in: context)
            } else {
                results = try await service.suggestions(for: context)
            }
            suggestions = results
        } catch {
            // Collapsing the row cancels the in-flight `.task`. That is not a
            // failure: recording it would strand a stale error on a row the
            // user simply closed, and block the retry on reopen.
            if !Task.isCancelled {
                // Fail soft: the editor says so, the rest of the card is fine.
                suggestions = []
                loadError = error.localizedDescription
            }
        }
        isLoading = false
    }

    // MARK: Formatting

    /// "8 g protein · 49 g carbs · 14 g fat", with fibre only when there is
    /// some — a row of zeroes is noise, not information.
    private var macroSplit: String {
        var parts = [
            "\(item.proteinGrams) g protein",
            "\(item.carbGrams) g carbs",
            "\(Int(item.extended.fatG.rounded())) g fat",
        ]
        if item.fiberGrams > 0 {
            parts.append("\(item.fiberGrams) g fibre")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Collapsed") {
    VStack {
        EditableScanItemRow(
            item: MockScanRepository.sampleMeal.items[0],
            context: FoodReplacementContext(
                replacing: 0,
                in: MockScanRepository.sampleMeal.items,
                plate: MockScanRepository.sampleMeal.plate
            ),
            service: MockFoodReplacementService(),
            isExpanded: false,
            onToggleEdit: {},
            onReplace: { _ in }
        )
    }
    .padding(TPCSpacing.lg)
    .background(TPCColor.surface)
}

#Preview("Expanded") {
    ScrollView {
        EditableScanItemRow(
            item: MockScanRepository.sampleMeal.items[1],
            context: FoodReplacementContext(
                replacing: 1,
                in: MockScanRepository.sampleMeal.items,
                plate: MockScanRepository.sampleMeal.plate
            ),
            service: MockFoodReplacementService(),
            isExpanded: true,
            onToggleEdit: {},
            onReplace: { _ in }
        )
        .padding(TPCSpacing.lg)
    }
    .background(TPCColor.surface)
}
