import SwiftUI

/// Review screen for a completed scan: what was detected, the numbers, and
/// Accept. Mirrors the approved wireframe: item rows with source badges,
/// then Calories and Protein tiles.
///
/// Items are editable in place. The scan result itself is never mutated — the
/// card holds an editable copy of the items, derives the totals from it, and
/// hands the derived result to `onAccept`, so what gets logged is what is on
/// screen.
struct ScanResultCard: View {
    let scan: ScanResult
    let errorMessage: String?
    let isSaving: Bool
    /// `nil` makes the item rows read-only (the volumetric beta passes nothing).
    let replacementService: (any FoodReplacementService)?
    let onAccept: (ScanResult) -> Void
    let onScanAgain: () -> Void

    @State private var editableItems: [ScanItem]
    @State private var editingIndex: Int?

    init(
        scan: ScanResult,
        errorMessage: String?,
        isSaving: Bool,
        replacementService: (any FoodReplacementService)? = nil,
        onAccept: @escaping (ScanResult) -> Void,
        onScanAgain: @escaping () -> Void
    ) {
        self.scan = scan
        self.errorMessage = errorMessage
        self.isSaving = isSaving
        self.replacementService = replacementService
        self.onAccept = onAccept
        self.onScanAgain = onScanAgain
        _editableItems = State(initialValue: scan.items)
    }

    /// The scan as edited. Identical to `scan` until the user changes something,
    /// so an untouched result still logs the server's own numbers.
    private var editedScan: ScanResult {
        scan.replacingItems(editableItems)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TPCSpacing.md) {
                if scan.modeMismatch {
                    mismatchBanner
                }

                switch scan.scanType {
                case .notFood:
                    notFoodCard
                case .water:
                    waterCard
                case .food, .beverage:
                    itemsCard
                    totalsTiles
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.danger)
                        .multilineTextAlignment(.center)
                }

                actions
            }
            .padding(.horizontal, TPCSpacing.screenMargin)
            .padding(.top, TPCSpacing.xs)
            .padding(.bottom, TPCSpacing.xl)
        }
        // A fresh scan landing in the same slot must not keep the old edits.
        .onChange(of: scan) { _, new in
            editableItems = new.items
            editingIndex = nil
        }
    }

    // MARK: Sections

    private var mismatchBanner: some View {
        HStack(alignment: .top, spacing: TPCSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TPCColor.warning)
            Text(mismatchText)
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textPrimary)
        }
        .padding(TPCSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TPCColor.warning.opacity(0.12),
            in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
        )
    }

    private var mismatchText: String {
        let actual: String
        switch scan.scanType {
        case .food: actual = "food"
        case .beverage: actual = "a beverage"
        case .water: actual = "water"
        case .notFood: actual = "not food or drink"
        }
        return "You picked \(scan.requestedMode), but this photo looks like \(actual). We will log what is actually there."
    }

    private var notFoodCard: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                Text("Nothing to log here")
                    .font(TPCFont.cardTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Text(scan.reason ?? "We could not spot any food or drink in this one. Try another photo and we will take a look.")
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
            }
        }
    }

    private var waterCard: some View {
        VStack(spacing: TPCSpacing.md) {
            RivaCard {
                VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                    Text("Water")
                        .font(TPCFont.cardTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                    if let water = scan.water {
                        Text("Looks like \(water.containerType.isEmpty ? "a container" : articled(water.containerType)) with about \(water.volumeOz) fl oz in it, roughly \(water.volumeMl) ml.")
                            .font(TPCFont.footnote)
                            .foregroundStyle(TPCColor.textSecondary)
                    }
                }
            }

            if let water = scan.water {
                HStack(spacing: TPCSpacing.sm) {
                    RivaStatTile(
                        caption: "Water",
                        systemImage: "drop",
                        value: "\(water.volumeOz)",
                        unit: "fl oz"
                    )
                    RivaStatTile(
                        caption: "Glasses",
                        systemImage: "cup.and.saucer",
                        value: glassesText(water.glasses),
                        unit: water.glasses == 1 ? "glass" : "glasses"
                    )
                }
            }
        }
    }

    private var itemsCard: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.md) {
                if let plate = scan.plate, !plate.isEmpty {
                    Text(plate)
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.textSecondary)
                }

                // Index identity is safe here: editing replaces an item in
                // place, so the row count never changes.
                ForEach(Array(editableItems.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Divider().overlay(TPCColor.fillNeutral)
                    }
                    EditableScanItemRow(
                        item: item,
                        context: FoodReplacementContext(
                            replacing: index,
                            in: editableItems,
                            plate: scan.plate
                        ),
                        service: isSaving ? nil : replacementService,
                        isExpanded: editingIndex == index,
                        onToggleEdit: { toggleEditing(index) },
                        onReplace: { replace(index, with: $0) }
                    )
                }
            }
        }
    }

    private var totalsTiles: some View {
        HStack(spacing: TPCSpacing.sm) {
            RivaStatTile(
                caption: "Calories",
                systemImage: "flame",
                value: editedScan.totals.calories.formatted(),
                unit: "kcal"
            )
            RivaStatTile(
                caption: "Protein",
                systemImage: "fork.knife",
                value: "\(editedScan.totals.proteinGrams)",
                unit: "g"
            )
        }
    }

    // MARK: Editing

    /// Only one row edits at a time — opening another closes the first.
    private func toggleEditing(_ index: Int) {
        withAnimation(.snappy(duration: 0.28)) {
            editingIndex = editingIndex == index ? nil : index
        }
    }

    /// Swaps one item and closes the editor. The totals tiles read from
    /// `editedScan`, so they re-roll inside this same animation.
    private func replace(_ index: Int, with suggestion: FoodSuggestion) {
        guard editableItems.indices.contains(index) else { return }
        withAnimation(.snappy(duration: 0.28)) {
            editableItems[index] = editableItems[index].replaced(with: suggestion)
            editingIndex = nil
        }
    }

    private var actions: some View {
        VStack(spacing: TPCSpacing.sm) {
            if scan.scanType != .notFood {
                Button {
                    onAccept(editedScan)
                } label: {
                    if isSaving {
                        ProgressView().tint(TPCColor.textOnBrand)
                    } else {
                        Text("Add to my day")
                    }
                }
                .buttonStyle(.rivaPrimary)
                .disabled(isSaving)
            }

            Button("Try another photo") { onScanAgain() }
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(TPCColor.brand)
                .disabled(isSaving)
        }
        .padding(.top, TPCSpacing.xs)
    }

    // MARK: Formatting

    private func glassesText(_ glasses: Double) -> String {
        glasses.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(glasses))
            : String(format: "%.1f", glasses)
    }

    /// "10 inch dinner plate" reads better as "a 10 inch dinner plate".
    private func articled(_ noun: String) -> String {
        let first = noun.lowercased().first
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        if noun.first?.isNumber == true { return "a \(noun)" }
        return (first.map(vowels.contains) ?? false) ? "an \(noun)" : "a \(noun)"
    }
}

#Preview("Meal result") {
    ZStack {
        TPCColor.background.ignoresSafeArea()
        ScanResultCard(
            scan: MockScanRepository.sampleMeal,
            errorMessage: nil,
            isSaving: false,
            replacementService: MockFoodReplacementService(),
            onAccept: { _ in },
            onScanAgain: {}
        )
    }
}

#Preview("Read only") {
    ZStack {
        TPCColor.background.ignoresSafeArea()
        ScanResultCard(
            scan: MockScanRepository.sampleMeal,
            errorMessage: nil,
            isSaving: false,
            onAccept: { _ in },
            onScanAgain: {}
        )
    }
}
