import AppKit
import SwiftUI

/// Borderless, non-activating panel at the bottom centre of the screen with
/// the mouse. Hosting the pill in a transparent 340 x 70 window lets the pill
/// change width and cast a shadow without resizing the window.
@MainActor
final class OverlayPanel {
    let model = OverlayModel()
    private let panel: NSPanel
    private var elapsedTimer: Timer?
    private var recordingStartedAt: Date?

    private static let size = NSSize(width: 340, height: 70)
    private static let bottomOffset: CGFloat = 24

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
        let host = NSHostingView(rootView: PillRoot(model: model))
        host.frame = NSRect(origin: .zero, size: OverlayPanel.size)
        panel.contentView = host
        panel.alphaValue = 0
    }

    private func reposition() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - OverlayPanel.size.width / 2, y: visible.minY + OverlayPanel.bottomOffset)
        panel.setFrameOrigin(origin)
    }

    func show(_ state: OverlayModel.State) {
        model.state = state
        model.copied = false
        if !panel.isVisible || panel.alphaValue == 0 { reposition() }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        switch state {
        case .arming:
            recordingStartedAt = Date()
            model.elapsedSeconds = 0
            model.level = 0
            elapsedTimer?.invalidate()
            elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let start = self.recordingStartedAt else { return }
                    self.model.elapsedSeconds = Int(Date().timeIntervalSince(start))
                }
            }
        case .transcribing, .cleaningUp, .copyPrompt, .learned, .undone, .hidden:
            elapsedTimer?.invalidate()
            elapsedTimer = nil
        default:
            break
        }
    }

    func hide() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        guard panel.isVisible else { model.state = .hidden; return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.24
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

private struct PillRoot: View {
    @Bindable var model: OverlayModel
    var body: some View {
        ZStack {
            Color.clear
            if model.state != .hidden {
                PillView(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
            }
        }
        .frame(width: 340, height: 70, alignment: .center)
        .animation(.spring(duration: 0.46, bounce: 0.1), value: model.state != .hidden)
    }
}
