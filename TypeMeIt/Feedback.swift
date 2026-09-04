import AppKit

/// Start and stop sounds. The NSSound instances are kept for the app's
/// lifetime; a released NSSound stops playing.
@MainActor
enum Feedback {
    enum Kind { case start, stop }

    private static let start = NSSound(named: "pop_start")
    private static let stop = NSSound(named: "pop_stop")

    static func play(_ kind: Kind) {
        let sound = kind == .start ? start : stop
        sound?.stop()
        sound?.volume = 1
        sound?.play()
    }
}
