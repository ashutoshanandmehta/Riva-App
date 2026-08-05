import SwiftUI

/// One chat bubble. `isUser` picks the fill, the text colour and which corner
/// carries the tail; the shape is built once and shared by fill and border.
struct CompanionBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 20, bottomLeadingRadius: isUser ? 20 : 6,
            bottomTrailingRadius: isUser ? 6 : 20, topTrailingRadius: 20
        )

        return Text(text)
            .font(TPCFont.body)
            .foregroundStyle(isUser ? TPCColor.textOnInversePrimary : TPCColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isUser ? TPCColor.surfaceInverse : TPCColor.surface, in: shape)
            .overlay(
                shape.strokeBorder(
                    isUser ? TPCColor.surfaceInverse : TPCColor.surfaceOutline,
                    lineWidth: 1
                )
            )
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

#Preview {
    VStack(spacing: 14) {
        CompanionBubble(text: "How's my nausea trending?", isUser: true)
        CompanionBubble(text: "Looks steady this week — no new flags in your check-ins.", isUser: false)
    }
    .padding()
    .background(TPCColor.background)
}
