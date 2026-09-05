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

/// The pill for the prompts and toasts after a dictation: 40 pt tall,
/// capsule, three columns with the label dead centre, an icon on the left,
/// the buttons on the right.
struct PillView: View {
    @Bindable var model: OverlayModel
    @Environment(\.colorScheme) private var scheme

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
        case .copyPrompt:
            Text("Nothing to paste into").font(.system(size: 12)).foregroundStyle(labelColor).lineLimit(1)
        case .learned(_, let label):
            Text(label).font(.system(size: 12)).foregroundStyle(labelColor).lineLimit(1)
        case .undone:
            Text("Undone").font(.system(size: 12)).foregroundStyle(labelColor)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var rightSlot: some View {
        switch model.state {
        case .copyPrompt:
            HStack(spacing: 8) {
                pillButton(model.copied ? "Copied" : "Copy") { model.onCopy?() }.disabled(model.copied)
                cancelButton
            }
        case .learned:
            HStack(spacing: 8) {
                pillButton("Undo") { model.onUndo?() }
                chip(size: 22, action: { model.onKeep?() }) {
                    Image("akar-check").resizable().frame(width: 11, height: 11)
                }
                .help("Keep")
            }
        default:
            Color.clear.frame(width: 22, height: 22)
        }
    }

    private var cancelButton: some View {
        chip(size: 22, action: { model.onCancel?() }) {
            Image("akar-cross").resizable().frame(width: 10, height: 10)
        }
        .help("Cancel")
    }

    private func chip<Content: View>(size: CGFloat, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .foregroundStyle(glyph)
                .frame(width: size, height: size)
                .background(Circle().fill(chipFill))
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
}
