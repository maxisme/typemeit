import AppKit
import SwiftUI

/// A puff of smoke that swells and shrinks around its centre. Rendered
/// entirely in `Puff.metal`; this view only supplies time and parameters.
///
/// Three ways to drive it:
/// - `level`: the microphone level in 0...1 as published by `AudioCapture`.
///   The puff follows it directly: a fast attack so every syllable shows,
///   a slower release so the cloud breathes out rather than snapping shut.
/// - `expansion`: a fixed value in 0...1 (0 = wisp, 1 = full cloud).
/// - neither: the puff breathes on its own.
struct PuffView: View {
    var level: Float? = nil
    /// How far each syllable pushes the puff out; 1 is the web's response.
    var reaction: Double = 1
    var expansion: Double? = nil
    var tint: Color = .white
    /// Length of one autonomous inhale + exhale, in seconds.
    var breathPeriod: Double = 4.2
    /// The smallest the autonomous breath lets the puff get, in 0...1; the
    /// breath runs from here to a full cloud.
    var breathFloor: Double = 0
    /// Where in its breath the puff starts, as a fraction of the period, so
    /// puffs side by side are not all inhaling together.
    var breathPhase: Double = 0
    /// Added to the clock, so puffs side by side show different smoke.
    var timeOffset: Double = 0
    /// When set, the puff renders this instant of its texture and does not
    /// animate. For stills such as the app icon.
    var frozenTime: Double? = nil
    /// When set, the puff arrives: at this instant it is a wisp, and over the
    /// next `arrivalDuration` seconds it grows to the size the level asks
    /// for, streaming its smoke outwards. Only used with `level`.
    var arrival: Date? = nil
    static let arrivalDuration = 0.5
    /// When set, the puff departs: from this instant it disperses over
    /// `departureDuration` seconds, its lobes blowing outwards and thinning
    /// to nothing at its resting size. Only used with `level`.
    var departure: Date? = nil
    static let departureDuration = 0.5

    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @State private var dynamics = Dynamics()
    @State private var trail = Trail()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || frozenTime != nil)) { ctx in
            let now = (frozenTime ?? ctx.date.timeIntervalSinceReferenceDate) + timeOffset
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
                        .float(Float(disperse(at: now))),
                        .color(tint)))
                }
        }
    }

    /// Compiles the shader ahead of its first frame, which otherwise stalls
    /// for a moment.
    static func compileShader() async throws {
        try await ShaderLibrary.puff(.float2(CGSize(width: 1, height: 1)), .float(0), .float(0.5), .float(0.5), .float(0), .float(0), .color(.white))
            .compile(as: .colorEffect)
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
            return dynamics.step(level: Double(level), reaction: reaction, swell: swell(at: now), at: now)
        }
        if reduceMotion { return Frame(expansion: 0.7, trail: 0.7, flow: 0) }
        let e = breathFloor + (1 - breathFloor) * PuffView.breath(at: t + breathPhase * breathPeriod, period: breathPeriod)
        return Frame(expansion: e, trail: trail.step(expansion: e, at: now), flow: PuffView.idleFlow(at: t, expansion: e))
    }

    /// Expansion added for the arrival: negative while the puff grows in
    /// from a wisp.
    private func swell(at now: TimeInterval) -> Double {
        guard let arrival else { return 0 }
        let rest = Dynamics.restExpansion(forLevel: 0)
        return -(rest - 0.05) * (1 - PuffView.progress(since: arrival, over: PuffView.arrivalDuration, at: now))
    }

    /// How far the departure has run, 0...1; the shader blows the puff apart
    /// by this much.
    private func disperse(at now: TimeInterval) -> Double {
        guard let departure, !reduceMotion else { return 0 }
        return PuffView.progress(since: departure, over: PuffView.departureDuration, at: now)
    }

    /// Smoothstepped 0...1 progress of a transition begun at `start`.
    private static func progress(since start: Date, over duration: Double, at now: TimeInterval) -> Double {
        let p = min(max((now - start.timeIntervalSinceReferenceDate) / duration, 0), 1)
        return p * p * (3 - 2 * p)
    }

    /// Peak-hold on the expansion with a slow decay, so a retreat leaves a
    /// trail behind for a second or two. A reference type so the timeline
    /// closure can update it without triggering a view update.
    final class Trail {
        private var value = 0.0
        private var lastTime: TimeInterval?
        private let tau: Double

        init(tau: Double = 1.4) { self.tau = tau }

        func step(expansion: Double, at now: TimeInterval) -> Double {
            defer { lastTime = now }
            guard let lastTime else { value = expansion; return value }
            let dt = min(max(now - lastTime, 0), 0.1)
            value += (expansion - value) * (1 - exp(-dt / tau))
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
    /// The level is followed with a fast attack and a slow release, and the
    /// expansion sits at `rest` plus `gain` times that envelope. The flow
    /// phase advances with every rise, so smoke streams out on each syllable
    /// and hangs between them. Calibrated on the puff bench against "to be
    /// honest": every syllable moves the cloud, none of them merge.
    ///
    /// A reference type so the timeline closure can update it without
    /// triggering a view update.
    final class Dynamics {
        static let attack = 0.012
        static let release = 0.22
        static let gain = 0.75
        static let rest = 0.44

        private var env = 0.0
        private var flow = 0.0
        private var lastTime: TimeInterval?
        private var lastSwell = 0.0
        private let trail = Trail(tau: 0.8)

        /// Resting size for a given level.
        nonisolated static func restExpansion(forLevel level: Double) -> Double {
            rest + gain * min(max(level, 0), 1)
        }

        /// `reaction` scales how far the level moves the puff; 1 is the
        /// calibrated response. `swell` is added for arrival and departure.
        func step(level: Double, reaction: Double = 1, swell: Double = 0, at now: TimeInterval) -> Frame {
            defer { lastTime = now; lastSwell = swell }
            guard let lastTime else {
                env = level
                let e = min(1, max(0.05, Dynamics.rest + Dynamics.gain * reaction * env + swell))
                return Frame(expansion: e, trail: trail.step(expansion: e, at: now), flow: flow)
            }
            let dt = min(max(now - lastTime, 0), 0.1)
            let tau = level > env ? Dynamics.attack : Dynamics.release
            let before = env
            env += (level - env) * (1 - exp(-dt / tau))
            let e = min(1, max(0.05, Dynamics.rest + Dynamics.gain * reaction * env + swell))
            flow += dt * (0.08 + 6 * max(0, env - before)) + 1.2 * (swell - lastSwell)
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
