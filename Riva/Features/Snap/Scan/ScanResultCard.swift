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
            VStack(spacing: RivaSpacing.md) {
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
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.danger)
                        .multilineTextAlignment(.center)
                }

                actions
            }
            .padding(.horizontal, RivaSpacing.screenMargin)
            .padding(.top, RivaSpacing.xs)
            .padding(.bottom, RivaSpacing.xl)
        }
    }

    // MARK: Sections

    private var mismatchBanner: some View {
        HStack(alignment: .top, spacing: RivaSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RivaColor.warning)
            Text(mismatchText)
                .font(RivaFont.footnote)
                .foregroundStyle(RivaColor.textPrimary)
        }
        .padding(RivaSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RivaColor.warning.opacity(0.12),
            in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
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
            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                Text("Nothing to log here")
                    .font(RivaFont.cardTitle)
                    .foregroundStyle(RivaColor.textPrimary)
                Text(scan.reason ?? "This photo does not look like food, a drink, or water.")
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }
        }
    }

    private var waterCard: some View {
        VStack(spacing: RivaSpacing.md) {
            RivaCard {
                VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                    Text("Water")
                        .font(RivaFont.cardTitle)
                        .foregroundStyle(RivaColor.textPrimary)
                    if let water = scan.water {
                        Text("Looks like \(water.containerType.isEmpty ? "a container" : articled(water.containerType)) holding about \(water.volumeOz) fl oz (\(water.volumeMl) ml).")
                            .font(RivaFont.footnote)
                            .foregroundStyle(RivaColor.textSecondary)
                    }
                }
            }

            if let water = scan.water {
                HStack(spacing: RivaSpacing.sm) {
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
            VStack(alignment: .leading, spacing: RivaSpacing.md) {
                if let plate = scan.plate, !plate.isEmpty {
                    Text("On \(articled(plate))")
                        .rivaOverline()
                }

                ForEach(Array(scan.items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Divider().overlay(RivaColor.fillNeutral)
                    }
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: ScanItem) -> some View {
        HStack(alignment: .top, spacing: RivaSpacing.sm) {
            VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                Text(item.name.capitalized)
                    .font(RivaFont.cardTitle)
                    .foregroundStyle(RivaColor.textPrimary)
                Text("\(item.portionDesc), about \(Int(item.portionGrams.rounded()))g")
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
                RivaBadge(
                    text: item.matched ? "Matched" : "AI estimate",
                    style: item.matched ? .brand : .neutral
                )
            }
            Spacer()
            VStack(alignment: .trailing, spacing: RivaSpacing.xxs) {
                Text("\(item.calories)")
                    .font(RivaFont.metricM)
                    .foregroundStyle(RivaColor.textPrimary)
                Text("kcal")
                    .font(RivaFont.metricUnit)
                    .foregroundStyle(RivaColor.textSecondary)
            }
        }
    }

    private var totalsTiles: some View {
        HStack(spacing: RivaSpacing.sm) {
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
        VStack(spacing: RivaSpacing.sm) {
            if scan.scanType != .notFood {
                Button {
                    onAccept()
                } label: {
                    if isSaving {
                        ProgressView().tint(RivaColor.textOnBrand)
                    } else {
                        Text("Accept")
                    }
                }
                .buttonStyle(.rivaPrimary)
                .disabled(isSaving)
            }

            Button("Scan again") { onScanAgain() }
                .font(RivaFont.captionEmphasized)
                .foregroundStyle(RivaColor.brand)
                .disabled(isSaving)
        }
        .padding(.top, RivaSpacing.xs)
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
        RivaColor.background.ignoresSafeArea()
        ScanResultCard(
            scan: MockScanRepository.sampleMeal,
            errorMessage: nil,
            isSaving: false,
            onAccept: {},
            onScanAgain: {}
        )
    }
}
