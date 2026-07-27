import UIKit

/// Keyboard control for cases SwiftUI's `@FocusState` cannot reach.
enum RivaKeyboard {

    /// Resigns whatever is currently first responder.
    ///
    /// The tab pages stay mounted (see `RootView.tabPage`) — a hidden tab's
    /// text field keeps first responder, so the keyboard stays up over a
    /// screen with nothing to tap to put it away. Anything that moves a
    /// focused field offscreen calls this.
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
}
