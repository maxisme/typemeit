// Timings of the "Learned words" toast on the recording overlay.

import Foundation

enum ToastTiming {
    /// How long the toast stays on screen before the frontend dismisses it.
    /// The frontend owns the real countdown so hovering the pill can pause it.
    static let timeout: Duration = .seconds(8)

    /// Backstop hide scheduled in case the frontend never dismisses (for
    /// example while the pill is left hovered).
    static let safetyHide: Duration = .seconds(60)

    /// How long the "Undone" confirmation stays visible after a click.
    static let undoneLinger: Duration = .milliseconds(900)
}
