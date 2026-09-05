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
/// the buttons on the right. Set like the rest of the design system: flat
/// paper, an ink hairline, mono lowercase labels, ink buttons, and the one
/// shadow the system allows.
struct PillView: View {
    @Bindable var model: OverlayModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            leftSlot.frame(minWidth: 24, alignment: .leading)
            Spacer(minLength: 0)
            centre
            Spacer(minLength: 0)
            rightSlot.frame(minWidth: 24, alignment: .trailing)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(width: model.width, height: 40)
        .background(Capsule().fill(DesignTokens.Colors.paper))
        .overlay(Capsule().strokeBorder(DesignTokens.Colors.ink, lineWidth: DesignTokens.hairline))
        .shadow(color: .black.opacity(scheme == .dark ? 0.32 : 0.14), radius: 14, y: 10)
        .animation(.spring(duration: 0.46, bounce: 0.1), value: model.width)
        .onHover { model.toastPaused = $0 }
    }

    // MARK: Slots

    @ViewBuilder private var leftSlot: some View {
        switch model.state {
        case .copyPrompt:
            Image("akar-clipboard").resizable().frame(width: 14, height: 14).foregroundStyle(DesignTokens.Colors.ink2)
        case .learned:
            Image("akar-circle-check").resizable().frame(width: 14, height: 14).foregroundStyle(DesignTokens.Colors.ink)
        default:
            Color.clear.frame(width: 24, height: 24)
        }
    }

    @ViewBuilder private var centre: some View {
        switch model.state {
        case .copyPrompt:
            label("nothing to paste into")
        case .learned(_, let text):
            label(text.lowercased())
        case .undone:
            label("undone")
        default:
            EmptyView()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(DesignTokens.Colors.ink2).lineLimit(1)
    }

    @ViewBuilder private var rightSlot: some View {
        switch model.state {
        case .copyPrompt:
            HStack(spacing: 6) {
                Button(model.copied ? "copied" : "copy") { model.onCopy?() }
                    .buttonStyle(InkButtonStyle(primary: true)).disabled(model.copied)
                cross(help: "Cancel") { model.onCancel?() }
            }
        case .learned:
            HStack(spacing: 6) {
                Button("undo") { model.onUndo?() }.buttonStyle(InkButtonStyle())
                cross(help: "Dismiss") { model.onKeep?() }
            }
        default:
            Color.clear.frame(width: 22, height: 22)
        }
    }

    /// The quiet dismiss: a cross with no outline, ink-2 until hovered.
    private func cross(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image("akar-cross").resizable().frame(width: 10, height: 10)
                .foregroundStyle(DesignTokens.Colors.ink2)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
