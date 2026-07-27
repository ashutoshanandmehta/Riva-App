import SwiftUI

/// Small sheet for editing the daily wellness minutes goal (the "/ 45"
/// numeral on the hero card). Saves through the existing goals route.
struct WellnessGoalSheet: View {
    let account: any AccountRepository
    let onSaved: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var goal: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(account: any AccountRepository, currentGoal: Int, onSaved: @escaping (Int) -> Void) {
        self.account = account
        self.onSaved = onSaved
        _goal = State(initialValue: min(max(currentGoal, 10), 180))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.md) {
            Text("Daily practice goal")
                .font(TPCFont.sectionTitle)
                .foregroundStyle(TPCColor.textPrimary)

            RivaCard {
                Stepper(value: $goal, in: 10...180, step: 5) {
                    HStack(alignment: .lastTextBaseline, spacing: TPCSpacing.xxs) {
                        Text("\(goal)")
                            .font(TPCFont.metricM)
                            .foregroundStyle(TPCColor.textPrimary)
                        Text("min / day")
                            .font(TPCFont.metricUnit)
                            .foregroundStyle(TPCColor.textSecondary)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.danger)
            }

            Button(isSaving ? "Saving…" : "Save goal") {
                Task { await save() }
            }
            .buttonStyle(.rivaPrimary)
            .disabled(isSaving)
        }
        .padding(TPCSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TPCColor.background)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            _ = try await account.updateGoals(GoalsUpdate(wellnessMinutesGoal: goal))
            onSaved(goal)
            dismiss()
        } catch {
            errorMessage = "Could not save. Try again."
        }
        isSaving = false
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        WellnessGoalSheet(account: MockAccountRepository(), currentGoal: 45) { _ in }
    }
}
