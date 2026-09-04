import AppKit
import SwiftUI

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { nsView.material = material }
}

/// The recording pill: 40 pt tall, capsule, three columns with the meter or
/// label dead centre, pin or skip on the left, cancel on the right.
struct PillView: View {
    @Bindable var model: OverlayModel
    @Environment(\.colorScheme) private var scheme
    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private var meterColor: Color { scheme == .dark ? Color(red: 1, green: 0.412, blue: 0.38) : Color(red: 0.824, green: 0.271, blue: 0.231) }
    private var labelColor: Color { scheme == .dark ? .white.opacity(0.62) : Color(white: 0.43) }
    private var chipFill: Color { scheme == .dark ? .white.opacity(0.12) : .black.opacity(0.07) }
    private var glyph: Color { scheme == .dark ? .white.opacity(0.75) : Color(white: 0.35) }

    var body: some View {
        HStack(spacing: 0) {
            leftSlot.frame(minWidth: 24, alignment: .leading)
            Spacer(minLength: 0)
            centre
            Spacer(minLength: 0)
            rightSlot.frame(minWidth: 24, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(width: model.width, height: 40)
        .background(
            ZStack {
                VisualEffect(material: .hudWindow)
                Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.22 : 0.9), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
            }
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(scheme == .dark ? 0.32 : 0.18), radius: 14, y: 10)
        .animation(.spring(duration: 0.46, bounce: 0.1), value: model.width)
        .onHover { model.toastPaused = $0 }
    }

    // MARK: Slots

    @ViewBuilder private var leftSlot: some View {
        switch model.state {
        case .arming, .recording:
            chip(size: 24, filled: false, dimmed: model.state == .arming, action: { model.onPin?() }) {
                Image("akar-pin").resizable().frame(width: 15, height: 15)
            }
            .help("Keep recording")
        case .pinned:
            chip(size: 24, filled: true, dimmed: false, action: { model.onStop?() }) {
                Image("akar-check").resizable().frame(width: 15, height: 15)
            }
            .help("Finish")
        case .cleaningUp:
            chip(size: 24, filled: false, dimmed: false, action: { model.onSkip?() }) {
                Image("akar-arrow-forward-thick").resizable().frame(width: 14, height: 14)
            }
            .help("Skip clean-up")
        case .copyPrompt:
            Image("akar-clipboard").resizable().frame(width: 15, height: 15).foregroundStyle(labelColor)
        case .learned:
            Image("akar-circle-check").resizable().frame(width: 15, height: 15).foregroundStyle(Color(red: 0.19, green: 0.82, blue: 0.35))
        default:
            Color.clear.frame(width: 24, height: 24)
        }
    }

    @ViewBuilder private var centre: some View {
        switch model.state {
        case .arming, .recording, .pinned:
            HStack(spacing: 10) {
                meter
                Text(timeString(model.elapsedSeconds))
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(scheme == .dark ? .white.opacity(0.45) : Color(white: 0.6))
            }
        case .transcribing:
            HStack(spacing: 8) {
                wave
                Text("Transcribing").font(.system(size: 12)).foregroundStyle(labelColor)
            }
        case .cleaningUp:
            HStack(spacing: 8) {
                dots
                shimmerLabel("Cleaning up")
            }
        case .copyPrompt:
            Text("Nothing to paste into").font(.system(size: 12)).foregroundStyle(labelColor).lineLimit(1)
        case .learned(_, let label):
            Text(label).font(.system(size: 12)).foregroundStyle(labelColor).lineLimit(1)
        case .undone:
            Text("Undone").font(.system(size: 12)).foregroundStyle(labelColor)
        case .hidden:
            EmptyView()
        }
    }

    @ViewBuilder private var rightSlot: some View {
        switch model.state {
        case .arming, .recording, .pinned, .transcribing, .cleaningUp:
            cancelButton
        case .copyPrompt:
            HStack(spacing: 8) {
                pillButton(model.copied ? "Copied" : "Copy") { model.onCopy?() }.disabled(model.copied)
                cancelButton
            }
        case .learned:
            HStack(spacing: 8) {
                pillButton("Undo") { model.onUndo?() }
                chip(size: 22, filled: false, dimmed: false, action: { model.onKeep?() }) {
                    Image("akar-check").resizable().frame(width: 11, height: 11)
                }
                .help("Keep")
            }
        default:
            Color.clear.frame(width: 22, height: 22)
        }
    }

    private var cancelButton: some View {
        chip(size: 22, filled: false, dimmed: false, action: { model.onCancel?() }) {
            Image("akar-cross").resizable().frame(width: 10, height: 10)
        }
        .help("Cancel")
    }

    private func chip<Content: View>(size: CGFloat, filled: Bool, dimmed: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .foregroundStyle(filled ? (scheme == .dark ? Color(white: 0.11) : .white) : (dimmed ? glyph.opacity(0.5) : glyph))
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? (scheme == .dark ? Color.white.opacity(0.92) : Color(white: 0.11)) : chipFill))
        }
        .buttonStyle(.plain)
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(scheme == .dark ? .white : Color(white: 0.11))
                .padding(.horizontal, 11)
                .frame(height: 22)
                .background(Capsule().fill(scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Meter and animations

    private static let barWeights: [Float] = [0.45, 0.8, 1.0, 0.6, 0.9, 0.5, 0.95, 0.7]

    private var meter: some View {
        HStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { i in
                let armed = model.state != .arming
                let h: CGFloat = armed ? CGFloat(3 + pow(Double(min(1, model.level * PillView.barWeights[i] * 1.6)), 0.7) * 15) : 6
                RoundedRectangle(cornerRadius: 2)
                    .fill(armed ? meterColor : labelColor.opacity(0.35))
                    .frame(width: 4, height: h)
                    .animation(.linear(duration: 0.08), value: h)
            }
        }
        .frame(height: 18)
    }

    private var wave: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<8, id: \.self) { i in
                    let phase = reduceMotion ? 0.55 : 0.28 + 0.72 * max(0, sin((t / 1.15 - Double(i) * 0.09) * 2 * .pi))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(labelColor.opacity(reduceMotion ? 0.8 : 0.45 + 0.55 * phase))
                        .frame(width: 4, height: 18 * phase)
                }
            }
            .frame(height: 18)
        }
    }

    private var dots: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<8, id: \.self) { i in
                    let o = reduceMotion ? 0.6 : 0.35 + 0.55 * (0.5 + 0.5 * sin((t / 1.4 - Double(i) * 0.11) * 2 * .pi))
                    Circle().fill(labelColor.opacity(o)).frame(width: 4, height: 4)
                }
            }
            .frame(height: 18)
        }
    }

    private func shimmerLabel(_ text: String) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let x = reduceMotion ? 0.5 : (t.truncatingRemainder(dividingBy: 2.1) / 2.1) * 2.2 - 0.6
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: labelColor.opacity(0.6), location: max(0, x - 0.3)),
                            .init(color: labelColor.opacity(1.0), location: max(0, min(1, x))),
                            .init(color: labelColor.opacity(0.6), location: min(1, x + 0.3)),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                )
        }
    }

    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}
