import AppKit
import SwiftUI

/// Borderless, non-activating panel at the bottom centre of the screen with
/// the mouse. The transparent 340 x 200 window sits on the bottom edge of
/// the visible screen, so the cloud has room to swell and the pill can
/// change width and cast a shadow without the window resizing.
@MainActor
final class OverlayPanel {
    let model = OverlayModel()
    private let panel: NSPanel

    static let size = NSSize(width: 360, height: 260)

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: OverlayPanel.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        let host = NSHostingView(rootView: OverlayRoot(model: model))
        host.frame = NSRect(origin: .zero, size: OverlayPanel.size)
        panel.contentView = host
        panel.alphaValue = 0
        // The first frame of the puff would otherwise wait for its shader to
        // compile, and the arrival is over in about a second.
        Task { try? await PuffView.compileShader() }
    }

    private func reposition() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - OverlayPanel.size.width / 2, y: visible.minY)
        panel.setFrameOrigin(origin)
    }

    func show(_ state: OverlayModel.State) {
        if state == .arming {
            model.level = 0
            model.shownAt = Date()
            model.departedAt = nil
        }
        model.state = state
        model.copied = false
        // The cloud has nothing to click until it is pinned, so let clicks
        // through to whatever is behind it until then.
        panel.ignoresMouseEvents = model.presentation == .cloud && state != .pinned
        if !panel.isVisible || panel.alphaValue == 0 { reposition() }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { model.state = .hidden; return }
        // The cloud shrinks as it goes; the fade lets it draw in before it is
        // gone. The pill just fades.
        let shrinking = model.presentation == .cloud
        if shrinking, model.departedAt == nil { model.departedAt = Date() }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = shrinking ? PuffView.departureDuration : 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.panel.alphaValue == 0 else { return }
                self.panel.orderOut(nil)
                self.model.state = .hidden
            }
        })
    }

    func setLevel(_ level: Float) { model.level = level }
}

private struct OverlayRoot: View {
    @Bindable var model: OverlayModel
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            switch model.presentation {
            case .cloud:
                CloudView(model: model)
                    .id(model.shownAt)
                    .transition(.opacity)
            case .pill:
                PillView(model: model)
                    .padding(.bottom, CloudView.restHeight - 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
            case .none:
                EmptyView()
            }
        }
        .frame(width: OverlayPanel.size.width, height: OverlayPanel.size.height, alignment: .bottom)
        .animation(.spring(duration: 0.46, bounce: 0.1), value: model.presentation)
    }
}
