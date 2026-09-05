import AppKit
import CoreGraphics
import Foundation

/// What the pipeline hears from the keyboard.
enum ShortcutEvent: Sendable {
    case recordingStarted
    case pinned
    case recordingEnded
    case cancelled
    /// Esc while post-processing: skip it and paste what we have.
    case skipRequested
    /// The user's copy-last-transcript shortcut, while idle.
    case copyLastRequested
}

/// One listen-only CGEvent tap. Fn is keycode 63 on flagsChanged. Space (49)
/// and Esc (53) are watched only while a recording is in progress.
@MainActor
final class Shortcuts {
    enum Phase: Sendable { case idle, recording, pinned, transcribing, cleaningUp }

    private(set) var phase: Phase = .idle
    private(set) var tapInstalled = false
    var onEvent: (@MainActor (ShortcutEvent) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsDown = false
    private var fnSeenUp = false
    private var fnDownAt: ContinuousClock.Instant?

    private static let fnKeycode: Int64 = 63
    private static let spaceKeycode: Int64 = 49
    private static let escKeycode: Int64 = 53

    /// Returns false when Input Monitoring has not been granted.
    @discardableResult
    func install() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: Shortcuts.callback, userInfo: userInfo)
        else {
            Log.shortcuts.error("Event tap could not be created; Input Monitoring is missing")
            tapInstalled = false
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapInstalled = true
        // Ignore an Fn that was already held when the tap appeared.
        fnSeenUp = !CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
        Log.shortcuts.info("Event tap installed")
        return true
    }

    func uninstall() {
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        runLoopSource = nil
        tapInstalled = false
    }

    /// The pipeline tells the shortcuts where it is so Esc means the right thing.
    func setPhase(_ p: Phase) { phase = p }

    /// The pill's pin button.
    func pinFromOverlay() {
        guard phase == .recording else { return }
        phase = .pinned
        onEvent?(.pinned)
    }

    /// The pill's stop button while pinned.
    func stopFromOverlay() {
        guard phase == .pinned else { return }
        phase = .transcribing
        onEvent?(.recordingEnded)
    }

    /// The menu's Start Recording. Opens the microphone already pinned, since
    /// there is no key to release.
    func startFromMenu() {
        guard phase == .idle else { return }
        phase = .pinned
        onEvent?(.recordingStarted)
        onEvent?(.pinned)
    }

    /// The menu's Stop Recording, whether the recording was pinned or Fn is
    /// still held.
    func stopFromMenu() {
        guard phase == .recording || phase == .pinned else { return }
        phase = .transcribing
        onEvent?(.recordingEnded)
    }

    func cancelFromOverlay() {
        guard phase != .idle else { return }
        phase = .idle
        onEvent?(.cancelled)
    }

    private struct EventBox: @unchecked Sendable { let event: CGEvent }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let shortcuts = Unmanaged<Shortcuts>.fromOpaque(userInfo).takeUnretainedValue()
        let box = EventBox(event: event)
        // The tap's run loop source lives on the main run loop, so this runs on the main thread.
        let passThrough = MainActor.assumeIsolated { shortcuts.handle(type: type, event: box.event) }
        return passThrough ? Unmanaged.passUnretained(event) : nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Shortcuts.fnKeycode else {
                return true
            }
            let down = event.flags.contains(.maskSecondaryFn)
            if down != fnIsDown {
                fnIsDown = down
                if down { fnDown() } else { fnUp() }
            }
            return true
        case .keyDown, .keyUp:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if phase == .idle, let combo = Settings.shared.copyLastShortcut, combo.matches(keyCode: keycode, flags: event.flags) {
                if type == .keyDown { onEvent?(.copyLastRequested) }
                return false  // swallow both so the key does not also reach the app underneath
            }
            if keycode == Shortcuts.spaceKeycode, fnIsDown || phase == .pinned, phase == .recording || phase == .pinned {
                if type == .keyDown, phase == .recording {
                    phase = .pinned
                    onEvent?(.pinned)
                }
                return false  // swallow both down and up so no space reaches the app underneath
            }
            if keycode == Shortcuts.escKeycode, type == .keyDown {
                switch phase {
                case .recording, .pinned, .transcribing:
                    phase = .idle
                    onEvent?(.cancelled)
                    return false
                case .cleaningUp:
                    onEvent?(.skipRequested)
                    return false
                case .idle:
                    break
                }
            }
            return true
        default:
            return true
        }
    }

    private func fnDown() {
        guard fnSeenUp else { return }
        switch phase {
        case .idle:
            fnDownAt = .now
            phase = .recording
            onEvent?(.recordingStarted)
        case .pinned:
            phase = .transcribing
            onEvent?(.recordingEnded)
        default:
            break
        }
    }

    private func fnUp() {
        fnSeenUp = true
        switch phase {
        case .recording:
            let held = fnDownAt.map { ContinuousClock.now - $0 } ?? .zero
            if held < .milliseconds(Fixed.holdThresholdMs) {
                phase = .idle
                onEvent?(.cancelled)  // a tap
            } else {
                phase = .transcribing
                onEvent?(.recordingEnded)
            }
        case .pinned:
            break  // the release is ignored while pinned
        default:
            break
        }
    }
}
