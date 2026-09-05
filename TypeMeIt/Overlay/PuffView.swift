import AppKit
import SwiftUI

/// A puff of smoke that swells and shrinks around its centre. Rendered
/// entirely in `Puff.metal`; this view only supplies time and parameters.
///
/// Pass `expansion` (0 = wisp, 1 = full cloud) to drive it from outside, for
/// example from the microphone level. Leave it nil and the puff breathes on
/// its own.
struct PuffView: View {
    var expansion: Double? = nil
    var tint: Color = .white
    /// Length of one autonomous inhale + exhale, in seconds.
    var breathPeriod: Double = 4.2

    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let e = expansion ?? (reduceMotion ? 0.7 : PuffView.breath(at: t, period: breathPeriod))
            Color.white
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.puff(
                        .float2(proxy.size),
                        .float(Float(t)),
                        .float(Float(e)),
                        .color(tint)))
                }
        }
    }

    /// Slow inhale, quicker exhale, a short hold at each end.
    static func breath(at t: Double, period: Double) -> Double {
        let phase = (t / period).truncatingRemainder(dividingBy: 1)
        let inhale = 0.58
        let x: Double
        if phase < inhale {
            x = phase / inhale
            return smootherstep(x)
        } else {
            x = (phase - inhale) / (1 - inhale)
            return 1 - smootherstep(x)
        }
    }

    private static func smootherstep(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * c * (c * (c * 6 - 15) + 10)
    }
}

#Preview("Breathing, dark") {
    PuffView()
        .frame(width: 240, height: 240)
        .background(Color(white: 0.08))
}

#Preview("Levels, light") {
    HStack(spacing: 0) {
        ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { e in
            PuffView(expansion: e, tint: Color(white: 0.25))
                .frame(width: 120, height: 120)
        }
    }
    .background(Color(white: 0.96))
}
