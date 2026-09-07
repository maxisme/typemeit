import AppKit
import SwiftUI

/// The recording indicator: a puff of smoke that grows from nothing at the
/// bottom of the screen and swells with each syllable. It stays, small,
/// still and thickened, with lightning flickering behind it once a second,
/// while the dictation is transcribed and cleaned up, then fades.
/// While pinned, a click on it finishes.
struct CloudView: View {
    @Bindable var model: OverlayModel
    @Environment(\.colorScheme) private var scheme
    @State private var grown = false
    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @State private var repel = Repel()

    /// Side of the square the puff is drawn in. The resting cloud is about a
    /// quarter of it across.
    static let size: CGFloat = 300
    /// Height of the cloud's centre above the bottom of the panel.
    static let restHeight: CGFloat = 84
    /// Drawn this much smaller as it grows in, on top of the puff's own
    /// change of expansion.
    static let arrivalScale: CGFloat = 0.3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { ctx in
            let now = ctx.date.timeIntervalSinceReferenceDate
            // The mouse relative to the cloud, as a fraction of the square
            // it is drawn in; screen coordinates run upwards, the puff's down.
            let mouse = NSEvent.mouseLocation
            let at = CGPoint(x: (mouse.x - model.cloudCentre.x) / CloudView.size,
                             y: (model.cloudCentre.y - mouse.y) / CloudView.size)
            PuffView(level: level(at: now), tint: tint,
                     arrival: model.shownAt, departure: model.departedAt,
                     strike: strike(at: ctx.date), density: 1 + (CloudView.processingDensity - 1) * settled(at: ctx.date),
                     settle: CloudView.processingSettle * settled(at: ctx.date),
                     hole: repel.step(at, at: now))
        }
        .animation(.easeInOut(duration: 0.2), value: model.backdrop)
        .frame(width: CloudView.size, height: CloudView.size)
        .contentShape(Circle().scale(0.45))
        .onTapGesture { if model.state == .pinned { model.onStop?() } }
        .onHover { inside in
            if inside, model.state == .pinned { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(model.state == .pinned ? "Finish" : "")
        .scaleEffect(grown ? 1 : CloudView.arrivalScale)
        .animation(.spring(duration: PuffView.arrivalDuration, bounce: 0.15), value: grown)
        .offset(y: CloudView.size / 2 - CloudView.restHeight)
        .onAppear {
            if reduceMotion {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { grown = true }
            } else {
                grown = true
            }
        }
    }

    private var isProcessing: Bool {
        switch model.state {
        case .transcribing, .cleaningUp: true
        default: false
        }
    }

    /// The microphone level while recording; once it has stopped, silence,
    /// so the cloud settles to its small resting size.
    private func level(at t: TimeInterval) -> Float {
        isProcessing ? 0 : model.level
    }

    /// Over the first half second of processing the cloud settles: smaller
    /// by this much expansion, and this much thicker.
    static let processingSettle = 0.2
    static let processingDensity = 1.9
    /// It lets go again as it departs, so a thin cloud drifts apart rather
    /// than a dense ball bursting.
    private func settled(at now: Date) -> Double {
        guard isProcessing, let struck = model.struckAt else { return 0 }
        let p = min(max(now.timeIntervalSince(struck) / 0.5, 0), 1)
        var s = p * p * (3 - 2 * p)
        if let departed = model.departedAt {
            let q = min(max(now.timeIntervalSince(departed) / PuffView.departureDuration, 0), 1)
            s *= 1 - q * q * (3 - 2 * q)
        }
        return s
    }

    /// Lightning strikes as the dictation ends, then once a second for as
    /// long as it is being processed. Each strike is a different one, since
    /// the shader seeds its route from the time.
    private func strike(at now: Date) -> Date? {
        guard let struck = model.struckAt else { return nil }
        guard isProcessing else { return struck }
        let elapsed = now.timeIntervalSince(struck)
        return struck.addingTimeInterval(max(0, floor(elapsed)))
    }

    /// The smoke keeps clear of the mouse: the cloud stays where it is, and
    /// the smoke within `radius` of the cursor is pushed out to sit around
    /// it, none of it lost. The hole opens and closes over `open` seconds
    /// and trails the cursor by `lag`, so it is smoke getting out of the
    /// way rather than a stencil. Positions are fractions of the square the
    /// puff is drawn in. Mirrored by `Repel` in web/index.html; change the
    /// constants together.
    ///
    /// A reference type so the timeline closure can update it without
    /// triggering a view update.
    final class Repel {
        static let radius = 0.025
        static let open = 0.2
        static let lag = 0.08

        private var hole = SIMD3<Float>.zero
        private var lastTime: TimeInterval?

        /// `point` is where the cursor is, or nil for no cursor.
        func step(_ point: CGPoint?, at now: TimeInterval) -> SIMD3<Float> {
            defer { lastTime = now }
            guard let lastTime else {
                if let point { hole = SIMD3(Float(point.x), Float(point.y), 0) }
                return hole
            }
            let dt = Float(min(max(now - lastTime, 0), 0.1))
            if let point {
                let k = 1 - exp(-dt / Float(Repel.lag))
                hole.x += (Float(point.x) - hole.x) * k
                hole.y += (Float(point.y) - hole.y) * k
            }
            let target: Float = point == nil ? 0 : Float(Repel.radius)
            hole.z += (target - hole.z) * (1 - exp(-dt / Float(Repel.open)))
            return hole
        }
    }

    /// The chosen colour, or white or dark grey against what is behind the
    /// cloud when that has been sampled, else with the appearance.
    private var tint: Color {
        let settings = Settings.shared
        let light = switch model.backdrop {
        case .light: false
        case .dark: true
        case nil: scheme == .dark
        }
        let base = settings.cloudColorEnabled ? settings.cloudColor.color : (light ? NSColor(white: 1, alpha: 1) : NSColor(white: 0.25, alpha: 1))
        return Color(nsColor: base)
    }
}
