import Foundation
import Observation

/// What the pill shows. Driven by the pipeline, read by PillView.
@MainActor
@Observable
final class OverlayModel {
    enum State: Equatable {
        case hidden
        case arming
        case recording
        case pinned
        case transcribing
        case cleaningUp
        case copyPrompt
        case learned(batchId: UUID, label: String)
        case undone
    }

    var state: State = .hidden
    var level: Float = 0
    var elapsedSeconds: Int = 0
    var copied = false
    var toastPaused = false

    /// Pill width per state, from the design.
    var width: CGFloat {
        switch state {
        case .hidden, .arming, .recording, .pinned: 200
        case .transcribing, .cleaningUp: 216
        case .copyPrompt: 300
        case .learned, .undone: 286
        }
    }

    var isRecording: Bool {
        switch state {
        case .arming, .recording, .pinned: true
        default: false
        }
    }

    // Actions wired by the pipeline.
    var onPin: (@MainActor () -> Void)?
    var onStop: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var onSkip: (@MainActor () -> Void)?
    var onCopy: (@MainActor () -> Void)?
    var onKeep: (@MainActor () -> Void)?
    var onUndo: (@MainActor () -> Void)?
}
