import SwiftUI

extension AttributedString {
    /// Parses a Markdown message and paints **strongly emphasized** runs in
    /// the brand color — the house style for AI coaching copy
    /// ("Tomorrow is **injection day**…").
    static func rivaHighlighted(markdown: String) -> AttributedString {
        guard var text = try? AttributedString(markdown: markdown) else {
            return AttributedString(markdown)
        }
        for run in text.runs {
            let isBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false
            if isBold {
                text[run.range].foregroundColor = RivaColor.brand
            }
        }
        return text
    }
}
