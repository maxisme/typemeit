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
    @State private var shy = Shy(radius: CloudView.size * (0.05 + 0.2 * PuffView.Dynamics.restExpansion(forLevel: 0)))

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
            // Screen coordinates run upwards, the offset downwards.
            let shift = reduceMotion ? .zero : shy.step(pointer: NSEvent.mouseLocation, centre: model.cloudCentre, at: now)
            PuffView(level: level(at: now), tint: tint,
                     arrival: model.shownAt, departure: model.departedAt,
                     strike: strike(at: ctx.date), density: 1 + (CloudView.processingDensity - 1) * settled(at: ctx.date),
                     settle: CloudView.processingSettle * settled(at: ctx.date))
                .offset(x: shift.x, y: -shift.y)
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

    /// The cloud shies away from the mouse: within a few radii of it, the
    /// whole cloud drifts a little in the opposite direction, and drifts back
    /// once the mouse leaves. The shift is at most `shift` of the cloud's
    /// radius and follows the mouse lazily, so it reads as smoke stirred by
    /// the cursor rather than a thing dodging it. Mirrored by `Shy` in
    /// web/index.html; change the constants together.
    ///
    /// A reference type so the timeline closure can update it without
    /// triggering a view update.
    final class Shy {
        static let reach = 3.2
        static let shift = 0.12
        static let toward = 0.4
        static let back = 0.7

        private(set) var offset = CGPoint.zero
        private var lastTime: TimeInterval?
        private let radius: CGFloat

        /// `radius` is the resting cloud's radius in the units of the points.
        init(radius: CGFloat) { self.radius = radius }

        /// The offset to draw the cloud at, in the units of the points.
        func step(pointer: CGPoint, centre: CGPoint, at now: TimeInterval) -> CGPoint {
            var target = CGPoint.zero
            let dx = centre.x - pointer.x, dy = centre.y - pointer.y
            let d = hypot(dx, dy)
            let reach = Shy.reach * radius
            if d > 1e-3, d < reach {
                let w = 1 - d / reach
                let push = Shy.shift * radius * w * w
                target = CGPoint(x: dx / d * push, y: dy / d * push)
            }
            defer { lastTime = now }
            guard let lastTime else { return offset }
            let dt = min(max(now - lastTime, 0), 0.1)
            let moving = hypot(target.x, target.y) > hypot(offset.x, offset.y)
            let k = 1 - exp(-dt / (moving ? Shy.toward : Shy.back))
            offset.x += (target.x - offset.x) * k
            offset.y += (target.y - offset.y) * k
            return offset
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
