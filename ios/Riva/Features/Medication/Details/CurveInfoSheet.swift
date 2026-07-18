import SwiftUI

/// Static explainer for the medication concentration curve.
struct CurveInfoSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DetailSheetHeader(title: "About the medication curve", onClose: onClose)

            ScrollView {
                VStack(spacing: RivaSpacing.sm) {
                    section(
                        heading: "What it shows",
                        text: "The curve is an estimate of how much medication is in your system at each point in the week."
                    )
                    section(
                        heading: "How it is estimated",
                        text: "The estimate comes from your logged dose history. The line rises after each shot you record and tapers gradually between doses as your body processes the medication."
                    )
                    section(
                        heading: "Keep in mind",
                        text: "This is an educational estimate, not a measurement, and it is never medical advice. If you have questions about your dose, talk with your clinician."
                    )
                }
                .padding(.horizontal, RivaSpacing.screenMargin)
                .padding(.top, RivaSpacing.xs)
                .padding(.bottom, RivaSpacing.xl)
            }
        }
        .padding(.top, RivaSpacing.sm)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(RivaColor.background)
    }

    private func section(heading: String, text: String) -> some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                Text(heading)
                    .rivaOverline()
                Text(text)
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textPrimary)
            }
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        CurveInfoSheet {}
    }
}
