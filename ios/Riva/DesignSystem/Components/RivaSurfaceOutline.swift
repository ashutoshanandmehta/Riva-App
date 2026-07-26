import SwiftUI

extension View {
    /// Hairline border for elevated surfaces (cards, rows, tiles).
    ///
    /// Uses the TPC forest-green-at-10% border, visible in both light and
    /// dark contexts — matches the `rgba(30,51,37,0.10)` convention in the
    /// design files.
    func tpcSurfaceOutline(cornerRadius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(TPCColor.surfaceOutline, lineWidth: 1)
        )
    }

    /// Legacy alias — remove call-site by call-site as screens are rebuilt.
    func rivaSurfaceOutline(cornerRadius: CGFloat) -> some View {
        tpcSurfaceOutline(cornerRadius: cornerRadius)
    }
}
