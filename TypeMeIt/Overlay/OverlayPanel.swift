import AppKit
import SwiftUI

/// Borderless, non-activating panel at the bottom centre of the screen with
/// the mouse, or against its left or right edge halfway up. The transparent 460 x 260 window sits on the bottom edge of
/// the visible screen, so the cloud has room to swell and the pill can
/// change width and cast a shadow without the window resizing.
@MainActor
final class OverlayPanel {
    let model = OverlayModel()
    private let panel: NSPanel

    static let size = NSSize(width: 460, height: 260)
    /// How far the cloud's centre sits in from the screen edge at a side.
    static let sideInset: CGFloat = 56

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

    /// The presentation the panel was last placed for. The cloud may sit at
    /// a side; the pill is always at the bottom centre, so a switch between
    /// them moves the panel.
    private var placedFor: OverlayModel.Presentation?

    private func reposition() {
        placedFor = model.presentation
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        // The cloud's centre is half the panel across and restHeight up, so
        // at a side the panel hangs partly off the screen to put the cloud
        // against the edge, halfway up.
        let half = OverlayPanel.size.width / 2
        let position = model.presentation == .cloud ? Settings.shared.cloudPosition : .centre
        let origin: NSPoint = switch position {
        case .left: NSPoint(x: visible.minX + OverlayPanel.sideInset - half, y: visible.midY - CloudView.restHeight)
        case .centre: NSPoint(x: visible.midX - half, y: visible.minY)
        case .right: NSPoint(x: visible.maxX - OverlayPanel.sideInset - half, y: visible.midY - CloudView.restHeight)
        }
        panel.setFrameOrigin(origin)
    }

    func show(_ state: OverlayModel.State) {
        if state == .arming {
            model.level = 0
            model.shownAt = Date()
            model.departedAt = nil
            model.backdrop = nil
        }
        model.state = state
        resample()
        model.copied = false
        // The cloud has nothing to click until it is pinned, so let clicks
        // through to whatever is behind it until then.
        panel.ignoresMouseEvents = model.presentation == .cloud && state != .pinned
        if !panel.isVisible || panel.alphaValue == 0 || placedFor != model.presentation { reposition() }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        sampling?.cancel()
        sampling = nil
        guard panel.isVisible else { model.state = .hidden; return }
        // The cloud disperses, fading itself out in the shader; the panel
        // only follows so it is fully clear by the end. The pill just fades.
        let dispersing = model.presentation == .cloud
        if dispersing, model.departedAt == nil { model.departedAt = Date() }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = dispersing ? PuffView.departureDuration : 0.24
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

    private var sampling: Task<Void, Never>?

    /// Samples the screen under the cloud once as it arrives, and every
    /// second while pinned since the user may change windows under it. Not
    /// while it is leaving, and not without the setting and the grant.
    private func resample() {
        sampling?.cancel()
        sampling = nil
        let wanted = model.presentation == .cloud && (model.state == .arming || model.state == .recording || model.state == .pinned)
        guard wanted, Settings.shared.cloudMatchesBackdrop, CGPreflightScreenCaptureAccess() else { return }
        let repeating = model.state == .pinned
        sampling = Task { [weak self] in
            repeat {
                guard let self, !Task.isCancelled else { return }
                let rect = cloudRect
                let number = panel.windowNumber
                if let backdrop = await ScreenSampler.sample(rect: rect, excluding: number), !Task.isCancelled {
                    model.backdrop = backdrop
                }
                guard repeating else { return }
                try? await Task.sleep(for: .seconds(1))
            } while !Task.isCancelled
        }
    }

    /// The cloud's clickable circle, in screen coordinates.
    private var cloudRect: NSRect {
        let diameter = CloudView.size * 0.45
        let centre = NSPoint(x: panel.frame.midX, y: panel.frame.minY + CloudView.restHeight)
        return NSRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2, width: diameter, height: diameter)
    }
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
