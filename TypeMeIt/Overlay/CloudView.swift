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
    @State private var stir = Stir()

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
            let gusts = stir.step(at, at: now)
            PuffView(level: level(at: now), tint: tint,
                     arrival: model.shownAt, departure: model.departedAt,
                     strike: strike(at: ctx.date), density: 1 + (CloudView.processingDensity - 1) * settled(at: ctx.date),
                     settle: CloudView.processingSettle * settled(at: ctx.date),
                     gusts: gusts)
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

    /// The mouse stirs the smoke: the cloud stays where it is, and the smoke
    /// is brushed along by the cursor as it passes through, closing again
    /// behind it. Every `spacing` of travel leaves a gust where the cursor
    /// was, shoving the smoke the way it was going by up to `shove` at full
    /// speed, and each gust fades over `fade` seconds so the smoke eases
    /// back. A still cursor stirs nothing. Positions are fractions of the
    /// square the puff is drawn in. Mirrored by `Stir` in web/index.html;
    /// change the constants together.
    ///
    /// A reference type so the timeline closure can update it without
    /// triggering a view update.
    final class Stir {
        static let spacing = 0.035
        static let shove = 0.028
        /// Cursor speed, in view widths per second, at which the shove is
        /// its strongest.
        static let fullSpeed = 3.0
        static let fade = 0.5
        static let capacity = 8

        private var gusts: [(x: Double, y: Double, dx: Double, dy: Double)] = []
        private var lastPoint: CGPoint?
        private var lastGust: CGPoint?
        private var lastTime: TimeInterval?

        /// The live gusts, four floats each as `PuffView.gusts` takes them.
        func step(_ point: CGPoint, at now: TimeInterval) -> [Float] {
            defer { lastTime = now; lastPoint = point }
            guard let lastTime, let lastPoint else { lastGust = point; return [] }
            let dt = min(max(now - lastTime, 0), 0.1)
            let decay = exp(-dt / Stir.fade)
            for i in gusts.indices { gusts[i].dx *= decay; gusts[i].dy *= decay }
            let from = lastGust ?? lastPoint
            let dx = point.x - from.x, dy = point.y - from.y
            let travelled = hypot(dx, dy)
            if travelled >= Stir.spacing, dt > 0 {
                let speed = hypot(point.x - lastPoint.x, point.y - lastPoint.y) / dt
                let strength = Stir.shove * min(1, speed / Stir.fullSpeed)
                gusts.append((point.x, point.y, dx / travelled * strength, dy / travelled * strength))
                if gusts.count > Stir.capacity { gusts.removeFirst() }
                lastGust = point
            }
            gusts.removeAll { hypot($0.dx, $0.dy) < 0.0005 }
            return gusts.flatMap { [Float($0.x), Float($0.y), Float($0.dx), Float($0.dy)] }
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
