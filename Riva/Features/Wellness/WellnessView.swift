import SwiftUI

/// Wellness tab — placeholder until wellbeing programs ship.
struct WellnessView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Wellness",
            icon: .asset("WellnessIcon"),
            blurb: "Mindfulness, movement, mood check-ins, and wellbeing programs tailored to your GLP-1 journey are coming soon."
        )
    }
}

#Preview {
    WellnessView()
}
