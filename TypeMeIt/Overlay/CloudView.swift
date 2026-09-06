import AppKit
import SwiftUI

/// The recording indicator: a puff of smoke that grows from nothing at the
/// bottom of the screen and swells with each syllable. It stays, small,
/// still and thickened, with lightning flickering behind it once a second,
/// while the dictation is transcribed and cleaned up, then disperses.
/// While pinned, a click on it finishes.
struct CloudView: View {
    @Bindable var model: OverlayModel
    @Environment(\.colorScheme) private var scheme
    @State private var grown = false
    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// Side of the square the puff is drawn in. The resting cloud is about a
    /// quarter of it across.
    static let size: CGFloat = 300
    /// Height of the cloud's centre above the bottom of the panel.
    static let restHeight: CGFloat = 84
    /// Drawn this much smaller as it grows in, on top of the puff's own
    /// change of expansion.
    static let arrivalScale: CGFloat = 0.3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isProcessing)) { ctx in
            PuffView(level: level(at: ctx.date.timeIntervalSinceReferenceDate), tint: tint,
                     arrival: model.shownAt, departure: model.departedAt,
                     strike: strike(at: ctx.date), density: 1 + (CloudView.processingDensity - 1) * settled(at: ctx.date),
                     settle: CloudView.processingSettle * settled(at: ctx.date))
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
    private func settled(at now: Date) -> Double {
        guard isProcessing, let struck = model.struckAt else { return 0 }
        let p = min(max(now.timeIntervalSince(struck) / 0.5, 0), 1)
        return p * p * (3 - 2 * p)
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
