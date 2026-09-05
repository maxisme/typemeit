import AppKit

/// Start, pin, stop and processing sounds. The NSSound instances are kept for the app's
/// lifetime; a released NSSound stops playing.
@MainActor
enum Feedback {
    enum Kind { case start, pin, stop, hum }

    private static let start = NSSound(named: "pop_start")
    private static let pin = NSSound(named: "pop_pin")
    private static let stop = NSSound(named: "pop_stop")
    private static let hum = NSSound(named: "pop_hum")

    static func play(_ kind: Kind) {
        let sound: NSSound? = switch kind {
        case .start: start
        case .pin: pin
        case .stop: stop
        case .hum: hum
        }
        sound?.stop()
        sound?.volume = 1
        sound?.play()
    }

    /// The hum follows the stop breath rather than sitting on top of it.
    static func playHumAfterStop() {
        let wait = stop?.duration ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { play(.hum) }
    }
}
