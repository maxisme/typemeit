import AppKit
import SwiftUI

/// A puff of smoke that swells and shrinks around its centre. Rendered
/// entirely in `Puff.metal`; this view only supplies time and parameters.
///
/// Three ways to drive it:
/// - `level`: the microphone level in 0...1 as published by `AudioCapture`.
///   Rising edges in the level kick the puff outwards; it then settles back
///   over about half a second. The resting size follows the average level
///   only slightly.
/// - `expansion`: a fixed value in 0...1 (0 = wisp, 1 = full cloud).
/// - neither: the puff breathes on its own.
struct PuffView: View {
    var level: Float? = nil
    var expansion: Double? = nil
    var tint: Color = .white
    /// Length of one autonomous inhale + exhale, in seconds.
    var breathPeriod: Double = 4.2

    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @State private var dynamics = Dynamics()
    @State private var trail = Trail()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { ctx in
            let now = ctx.date.timeIntervalSinceReferenceDate
            let t = reduceMotion ? 0 : now.truncatingRemainder(dividingBy: 3600)
            let s = state(at: now)
            Color.white
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.puff(
                        .float2(proxy.size),
                        .float(Float(t)),
                        .float(Float(s.expansion)),
                        .float(Float(s.trail)),
                        .float(Float(s.flow)),
                        .color(tint)))
                }
        }
    }

    /// What the shader needs for one frame.
    struct Frame {
        var expansion: Double
        /// The expansion the puff is retreating from; fragments are left
        /// between the two radii. Equal to `expansion` when not retreating.
        var trail: Double
        var flow: Double
    }

    private func state(at now: TimeInterval) -> Frame {
        let t = now.truncatingRemainder(dividingBy: 3600)
        if let expansion { return Frame(expansion: expansion, trail: expansion, flow: PuffView.idleFlow(at: t, expansion: expansion)) }
        if let level {
            if reduceMotion {
                let e = Dynamics.restExpansion(forLevel: Double(level))
                return Frame(expansion: e, trail: e, flow: 0)
            }
            return dynamics.step(level: Double(level), at: now)
        }
        if reduceMotion { return Frame(expansion: 0.7, trail: 0.7, flow: 0) }
        let e = PuffView.breath(at: t, period: breathPeriod)
        return Frame(expansion: e, trail: trail.step(expansion: e, at: now), flow: PuffView.idleFlow(at: t, expansion: e))
    }

    /// Peak-hold on the expansion with a slow decay, so a retreat leaves a
    /// trail behind for a second or two. A reference type so the timeline
    /// closure can update it without triggering a view update.
    final class Trail {
        private var value = 0.0
        private var lastTime: TimeInterval?

        func step(expansion: Double, at now: TimeInterval) -> Double {
            defer { lastTime = now }
            guard let lastTime else { value = expansion; return value }
            let dt = min(max(now - lastTime, 0), 0.1)
            value += (expansion - value) * (1 - exp(-dt / 1.4))
            value = max(value, expansion)
            return value
        }
    }

    /// Slow constant drift plus a term that follows expansion, for the fixed
    /// and breathing modes.
    private static func idleFlow(at t: Double, expansion: Double) -> Double {
        t * 0.11 + 1.3 * expansion
    }

    // MARK: Level dynamics

    /// Turns the microphone level into expansion and flow.
    ///
    /// The level is tracked with a fast and a slow average; their difference
    /// is the onset of a syllable. Onsets drive a heavily damped spring: the
    /// puff is pushed out sharply and settles back over about a second. While
    /// it moves outwards the flow phase advances quickly, so the smoke streams
    /// out on the push and hangs while it settles. The resting size follows
    /// the slow average only a little.
    ///
    /// A reference type so the timeline closure can update it without
    /// triggering a view update.
    final class Dynamics {
        private var fast = 0.0
        private var slow = 0.0
        private var x = 0.0
        private var v = 0.0
        private var flow = 0.0
        private var lastTime: TimeInterval?
        private let trail = Trail()

        /// Resting size for a given slow average level.
        nonisolated static func restExpansion(forLevel level: Double) -> Double {
            0.34 + 0.12 * min(max(level, 0), 1)
        }

        func step(level: Double, at now: TimeInterval) -> Frame {
            defer { lastTime = now }
            guard let lastTime else {
                let e = Dynamics.restExpansion(forLevel: level)
                return Frame(expansion: e, trail: trail.step(expansion: e, at: now), flow: flow)
            }
            let dt = min(max(now - lastTime, 0), 0.1)

            fast += (level - fast) * (1 - exp(-dt / 0.025))
            slow += (level - slow) * (1 - exp(-dt / 0.30))
            let onset = max(0, fast - slow - 0.03)

            // Heavily damped spring: a sharp push out, then a settle over about
            // a second with no bounce.
            let omega = 7.0
            let zeta = 0.9
            let force = onset * 170.0
            let a = force - 2 * zeta * omega * v - omega * omega * x
            v += a * dt
            x += v * dt

            let e = min(1, max(0.05, Dynamics.restExpansion(forLevel: slow) + 0.4 * x))
            flow += dt * (0.08 + 1.2 * max(0, v))
            return Frame(expansion: e, trail: trail.step(expansion: e, at: now), flow: flow)
        }
    }

    // MARK: Autonomous breath

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
