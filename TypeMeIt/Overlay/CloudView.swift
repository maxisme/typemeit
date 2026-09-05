import AppKit
import SwiftUI

/// The recording indicator: a puff of smoke that grows from nothing at the
/// bottom of the screen and swells with each syllable. It stays, pulsing
/// slowly, while the dictation is transcribed and cleaned up, turning a
/// little blue for the clean-up, then shrinks away.
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
    /// Drawn this much smaller as it grows in and shrinks out, on top of the
    /// puff's own change of expansion.
    static let arrivalScale: CGFloat = 0.3
    static let departureScale: CGFloat = 0.5

    var body: some View {
        let departing = model.departedAt != nil
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isProcessing)) { ctx in
            PuffView(level: level(at: ctx.date.timeIntervalSinceReferenceDate), tint: tint,
                     arrival: model.shownAt, departure: model.departedAt)
        }
        .frame(width: CloudView.size, height: CloudView.size)
        .contentShape(Circle().scale(0.45))
        .onTapGesture { if model.state == .pinned { model.onStop?() } }
        .onHover { inside in
            if inside, model.state == .pinned { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(model.state == .pinned ? "Finish" : "")
        .scaleEffect(departing ? CloudView.departureScale : (grown ? 1 : CloudView.arrivalScale))
        .animation(.spring(duration: PuffView.arrivalDuration, bounce: 0.15), value: grown)
        .animation(.easeIn(duration: PuffView.departureDuration), value: departing)
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

    /// The microphone level while recording; once it has stopped, a slow
    /// pulse so the cloud visibly works while there is nothing to hear.
    private func level(at t: TimeInterval) -> Float {
        guard isProcessing else { return model.level }
        return Float(0.3 + 0.3 * sin(t * 2 * .pi / 1.8))
    }

    /// The chosen colour, or white or dark grey with the appearance; leaning
    /// a little towards green while the transcript is being cleaned up.
    private var tint: Color {
        let settings = Settings.shared
        let base = settings.cloudColorEnabled ? settings.cloudColor.color : (scheme == .dark ? NSColor(white: 1, alpha: 1) : NSColor(white: 0.25, alpha: 1))
        guard model.state == .cleaningUp else { return Color(nsColor: base) }
        let green = scheme == .dark ? NSColor(srgbRed: 0.55, green: 0.85, blue: 0.62, alpha: 1) : NSColor(srgbRed: 0.18, green: 0.45, blue: 0.28, alpha: 1)
        return Color(nsColor: base.blended(withFraction: 0.35, of: green) ?? base)
    }
}
