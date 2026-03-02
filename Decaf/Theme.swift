import SwiftUI

/// Design tokens for Decaf's calm gallery aesthetic.
/// All colours are warm-tinted neutrals; nothing is saturated or urgent.
enum Theme {

    // MARK: - Backgrounds

    /// Warm linen — the canvas every card is painted on.
    static let background = Color(red: 0.961, green: 0.941, blue: 0.922)

    // MARK: - Text

    /// Deep warm brown — used for titles and primary labels.
    static let ink     = Color(red: 0.239, green: 0.208, blue: 0.188)
    /// Medium warm gray — body copy, artist names.
    static let body    = Color(red: 0.482, green: 0.443, blue: 0.416)
    /// Pale warm gray — dates, captions, supporting detail.
    static let muted   = Color(red: 0.659, green: 0.616, blue: 0.592)

    // MARK: - Structure

    /// Hairline rule for separating image from caption.
    static let hairline = Color(red: 0.851, green: 0.824, blue: 0.796)


}
