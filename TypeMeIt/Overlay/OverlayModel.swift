import Foundation
import Observation

/// What the overlay shows. Driven by the pipeline, read by CloudView and
/// PillView.
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
        case learned(batchId: UUID, words: [String])
        case undone
    }

    /// Which view a state is shown in: the dictation itself is the cloud,
    /// the prompts and toasts afterwards are the pill.
    enum Presentation: Equatable { case none, cloud, pill }

    var state: State = .hidden
    var level: Float = 0
    var copied = false
    var toastPaused = false
    /// When the cloud last arrived. Each dictation gets a new one, so the
    /// cloud grows in again even if the previous one had not finished fading.
    var shownAt: Date?
    /// When the cloud started to puff out, or nil while it is still wanted.
    var departedAt: Date?
    /// When lightning last struck the cloud: as the dictation ended and
    /// transcription began.
    var struckAt: Date?
    /// What is under the cloud, when the screen has been sampled. Nil falls
    /// back to the appearance.
    var backdrop: ScreenSampler.Backdrop?

    var presentation: Presentation {
        switch state {
        case .hidden: .none
        case .arming, .recording, .pinned, .transcribing, .cleaningUp: .cloud
        case .copyPrompt, .learned, .undone: .pill
        }
    }

    /// Pill width per state, from the design.
    var width: CGFloat {
        switch state {
        case .copyPrompt: 368
        default: 320
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
