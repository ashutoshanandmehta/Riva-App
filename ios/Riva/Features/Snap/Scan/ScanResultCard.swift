import SwiftUI

/// Review screen for a completed scan: what was detected, the numbers, and
/// Accept. Mirrors the approved wireframe: item rows with source badges,
/// then Calories and Protein tiles.
struct ScanResultCard: View {
    let scan: ScanResult
    let errorMessage: String?
    let isSaving: Bool
    let onAccept: () -> Void
    let onScanAgain: () -> Void

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
        return "Heads up: you chose to log \(scan.requestedMode), but this looks like \(actual). Accept logs what is actually in the photo."
    }

    private var notFoodCard: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                Text("Nothing to log here")
                    .font(TPCFont.cardTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Text(scan.reason ?? "This photo does not look like food, a drink, or water.")
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
                        Text("Looks like \(water.containerType.isEmpty ? "a container" : articled(water.containerType)) holding about \(water.volumeOz) fl oz (\(water.volumeMl) ml).")
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

                ForEach(Array(scan.items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Divider().overlay(TPCColor.fillNeutral)
                    }
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: ScanItem) -> some View {
        HStack(alignment: .top, spacing: TPCSpacing.sm) {
            VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                Text(item.name.capitalized)
                    .font(TPCFont.cardTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Text("\(item.portionDesc), about \(Int(item.portionGrams.rounded()))g")
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
                RivaBadge(
                    text: item.matched ? "Matched" : "AI estimate",
                    style: item.matched ? .brand : .neutral
                )
            }
            Spacer()
            VStack(alignment: .trailing, spacing: TPCSpacing.xxs) {
                Text("\(item.calories)")
                    .font(TPCFont.metricM)
                    .foregroundStyle(TPCColor.textPrimary)
                Text("kcal")
                    .font(TPCFont.metricUnit)
                    .foregroundStyle(TPCColor.textSecondary)
            }
        }
    }

    private var totalsTiles: some View {
        HStack(spacing: TPCSpacing.sm) {
            RivaStatTile(
                caption: "Calories",
                systemImage: "flame",
                value: scan.totals.calories.formatted(),
                unit: "kcal"
            )
            RivaStatTile(
                caption: "Protein",
                systemImage: "fork.knife",
                value: "\(scan.totals.proteinGrams)",
                unit: "g"
            )
        }
    }

    private var actions: some View {
        VStack(spacing: TPCSpacing.sm) {
            if scan.scanType != .notFood {
                Button {
                    onAccept()
                } label: {
                    if isSaving {
                        ProgressView().tint(TPCColor.textOnBrand)
                    } else {
                        Text("Accept")
                    }
                }
                .buttonStyle(.rivaPrimary)
                .disabled(isSaving)
            }

            Button("Scan again") { onScanAgain() }
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
            onAccept: {},
            onScanAgain: {}
        )
    }
}
