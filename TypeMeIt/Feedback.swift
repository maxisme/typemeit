import AppKit

/// Pin and stop sounds. The NSSound instances are kept for the app's
/// lifetime; a released NSSound stops playing.
@MainActor
enum Feedback {
    enum Kind { case pin, stop }

    private static let pin = NSSound(named: "pop_pin")
    private static let stop = NSSound(named: "pop_stop")

    /// Touch every sound so the first play does not wait on disk.
    static func preload() {
        _ = pin; _ = stop
    }

    static func duration(_ kind: Kind) -> TimeInterval {
        switch kind {
        case .pin: pin?.duration ?? 0
        case .stop: stop?.duration ?? 0
        }
    }

    static func play(_ kind: Kind) {
        let sound: NSSound? = switch kind {
        case .pin: pin
        case .stop: stop
        }
        sound?.stop()
        sound?.volume = 0.2
        sound?.play()
    }
}
