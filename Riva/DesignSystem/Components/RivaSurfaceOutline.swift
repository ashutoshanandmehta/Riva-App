import SwiftUI

extension View {
    /// Hairline border for elevated surfaces (cards, rows, tiles).
    ///
    /// Invisible in light mode, where drop shadows provide separation; in
    /// dark mode shadows vanish against the dark background, so this faint
    /// stroke keeps surfaces legible. Apply after the surface's
    /// `background`/`clipShape` with the same corner radius.
    func rivaSurfaceOutline(cornerRadius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(RivaColor.surfaceOutline, lineWidth: 1)
        )
    }
}
