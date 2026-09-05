import AppKit
import Foundation
import Observation

/// One dictation from Fn down to paste, and everything the pill needs to know.
@MainActor
@Observable
final class Pipeline {
    static let shared = Pipeline()

    enum Phase: Equatable { case idle, recording, transcribing, cleaningUp }
    private(set) var phase: Phase = .idle

    let shortcuts = Shortcuts()
    let overlay = OverlayPanel()
    let capture = AudioCapture()
    private var settings: Settings { Settings.shared }
    private var store: Store { Store.shared }

    private var recordingStartedAt: Date?
    private var pinned = false
    private var generation = 0
    private var copyPromptTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var lastRecordingFirstBuffer = false

    private init() {
        shortcuts.onEvent = { [weak self] event in self?.handle(event) }
        capture.onLevel = { [weak self] level in
            Task { @MainActor in self?.overlay.setLevel(level) }
        }
        capture.onFirstBuffer = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlay.model.state == .arming else { return }
                self.overlay.show(.recording)
            }
        }
        overlay.model.onPin = { [weak self] in self?.shortcuts.pinFromOverlay() }
        overlay.model.onStop = { [weak self] in self?.shortcuts.stopFromOverlay() }
        overlay.model.onCancel = { [weak self] in
            guard let self else { return }
            if case .copyPrompt = self.overlay.model.state { self.dismissCopyPrompt(); return }
            if case .learned = self.overlay.model.state { self.keepLearned(); return }
            self.shortcuts.cancelFromOverlay()
        }
        overlay.model.onSkip = { [weak self] in self?.skipPostProcessing() }
        overlay.model.onCopy = { [weak self] in self?.copyFromPrompt() }
        overlay.model.onKeep = { [weak self] in self?.keepLearned() }
        overlay.model.onUndo = { [weak self] in self?.undoLearned() }
    }

    func start() {
        Feedback.preload()
        if !shortcuts.install() {
            Log.app.error("Shortcuts not installed; Input Monitoring is missing")
        }
        if settings.alwaysOnMicrophone { capture.warmUp(uid: settings.microphoneUID) }
    }

    func applyMicrophoneSettings() {
        if settings.alwaysOnMicrophone { capture.warmUp(uid: settings.microphoneUID) } else { capture.coolDown() }
    }

    var isBusy: Bool { phase != .idle }

    // MARK: Events

    private func handle(_ event: ShortcutEvent) {
        switch event {
        case .recordingStarted: beginRecording()
        case .pinned:
            pinned = true
            if settings.audioFeedback { playWhileMuted(.pin) }
            if overlay.model.isRecording { overlay.show(.pinned) }
        case .recordingEnded: endRecording()
        case .cancelled: cancel()
        case .skipRequested: skipPostProcessing()
        case .copyLastRequested: copyLast()
        }
    }

    /// The newest transcript with any text goes to the clipboard.
    private func copyLast() {
        guard let entry = Store.shared.history.last(where: { !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
        Output.copyToClipboard(entry.displayText)
        Log.app.info("Copied the newest transcript by shortcut")
    }

    /// The output device is muted while recording, so a cue played then has
    /// to lift the mute, sound, and put it back.
    private func playWhileMuted(_ kind: Feedback.Kind) {
        let gen = generation
        let wasMuted = OutputMute.restore()
        let wait = wasMuted ? 0.08 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { Feedback.play(kind) }
        guard wasMuted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait + Feedback.duration(kind)) { [weak self] in
            if self?.phase == .recording, self?.generation == gen { OutputMute.mute() }
        }
    }

    private func beginRecording() {
        guard phase == .idle else { return }
        generation += 1
        phase = .recording
        pinned = false
        recordingStartedAt = Date()
        copyPromptTask?.cancel()
        toastTask?.cancel()
        ReadBack.shared.finishNow()
        shortcuts.setPhase(.recording)
        if settings.muteWhileRecording { OutputMute.mute() }
        do {
            try capture.start(uid: settings.microphoneUID)
        } catch {
            Log.audio.error("Could not start capture: \(error.localizedDescription)")
            phase = .idle
            shortcuts.setPhase(.idle)
            OutputMute.restore()
            return
        }
        overlay.show(.arming)
        if settings.postProcessingEnabled { Task { await PostProcessor.shared.prewarm() } }
        Task { await Transcriber.shared.preload() }
    }

    private func cancel() {
        let wasRecording = phase == .recording
        generation += 1
        phase = .idle
        shortcuts.setPhase(.idle)
        if wasRecording { capture.cancel() }
        OutputMute.restore()
        Task { Transcriber.shared.cancel() }
        PostProcessor.shared.cancel()
        overlay.hide()
    }

    private func endRecording() {
        guard phase == .recording else { return }
        let gen = generation
        let pcm = capture.stop()
        let duration = Double(pcm.count) / 16000
        let durationMs = Int(duration * 1000)
        let wasMuted = OutputMute.restore()
        if settings.audioFeedback {
            // The device takes a moment to come back from mute; a cue played
            // in the same instant is lost.
            let wait = wasMuted ? 0.08 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { Feedback.play(.stop) }
        }

        if duration < Fixed.minimumRecordingSeconds || AudioCapture.peak(pcm) < Fixed.silencePeak {
            Log.app.info("Empty recording discarded (\(duration) s)")
            phase = .idle
            shortcuts.setPhase(.idle)
            overlay.hide()
            return
        }

        let target = Frontmost.capture()
        phase = .transcribing
        shortcuts.setPhase(.transcribing)
        overlay.show(.transcribing)

        Task { [weak self] in
            guard let self else { return }
            let raw: String
            let transcribeStart = ContinuousClock.now
            do {
                raw = try await Transcriber.shared.transcribe(pcm)
            } catch {
                if gen == self.generation {
                    Log.transcriber.error("\(error.localizedDescription)")
                    self.finishIdle()
                }
                return
            }
            guard gen == self.generation else { return }
            let transcribeMs = Pipeline.elapsedMs(since: transcribeStart)
            Log.transcriber.info("Transcribed \(durationMs) ms of audio in \(transcribeMs) ms")
            await self.deliver(raw: raw, durationMs: durationMs, transcribeMs: transcribeMs, target: target, generation: gen)
        }
    }

    private func finishIdle() {
        phase = .idle
        shortcuts.setPhase(.idle)
        overlay.hide()
    }

    private static func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let d = ContinuousClock.now - start
        return Int(d.components.seconds * 1000) + Int(d.components.attoseconds / 1_000_000_000_000_000)
    }

    private func deliver(raw: String, durationMs: Int, transcribeMs: Int, target: Frontmost.Target?, generation gen: Int) async {
        if TextCleanup.isBlank(raw) { finishIdle(); return }
        let customWords = settings.customWords
        let cleaned = TextCleanup.run(raw, customWords: customWords, aliases: store.aliases(customWords: customWords), threshold: Fixed.wordCorrectionThreshold)
        var finalText = cleaned.text
        var postProcessed: String?
        var postProcessMs: Int?
        let requested = settings.postProcessingEnabled

        if requested {
            phase = .cleaningUp
            shortcuts.setPhase(.cleaningUp)
            overlay.show(.cleaningUp)
            let start = ContinuousClock.now
            postProcessed = await PostProcessor.shared.run(cleaned.text, customWords: customWords)
            let ms = Pipeline.elapsedMs(since: start)
            postProcessMs = ms
            Log.postProcess.info("Post-processing took \(ms) ms (\(postProcessed == nil ? "fell back to local cleanup" : "applied"))")
            guard gen == generation else { return }
            if let postProcessed { finalText = postProcessed }
        }

        if settings.appendTrailingSpace { finalText += " " }
        let focusedIsTextInput = Focus.focusedElementIsTextInput()
        let pasted = await Output.paste(finalText, autoSubmit: settings.autoSubmit, autoSubmitKey: settings.autoSubmitKey)
        guard gen == generation else { return }

        let entry = HistoryEntry(
            timestamp: Date(), transcript: cleaned.text, postProcessed: postProcessed, postProcessRequested: requested,
            durationMs: durationMs, transcribeMs: transcribeMs, postProcessMs: postProcessMs, appId: target?.appId, appName: target?.appName, windowTitle: target?.windowTitle,
            dictionaryFixes: cleaned.dictionaryFixes)
        store.append(entry, limit: settings.historyLimit)

        phase = .idle
        shortcuts.setPhase(.idle)

        if pasted, focusedIsTextInput == true, settings.learnFromCorrections {
            ReadBack.shared.start(pasted: finalText, historyId: entry.id, appId: target?.appId)
        }

        if settings.copyPromptEnabled, !pasted || focusedIsTextInput == false {
            showCopyPrompt(finalText)
        } else {
            overlay.hide()
        }
    }

    private func skipPostProcessing() {
        guard phase == .cleaningUp else { return }
        PostProcessor.shared.cancel()
    }

    // MARK: Copy prompt

    private var copyPromptText = ""

    private func showCopyPrompt(_ text: String) {
        copyPromptText = text
        overlay.show(.copyPrompt)
        copyPromptTask?.cancel()
        copyPromptTask = Task { [weak self] in
            try? await Task.sleep(for: Fixed.copyPromptTimeout)
            guard !Task.isCancelled, let self, case .copyPrompt = self.overlay.model.state else { return }
            self.overlay.hide()
        }
    }

    private func copyFromPrompt() {
        Output.copyToClipboard(copyPromptText)
        overlay.model.copied = true
        copyPromptTask?.cancel()
        copyPromptTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.overlay.hide()
        }
    }

    private func dismissCopyPrompt() {
        copyPromptTask?.cancel()
        overlay.hide()
    }

    func copyLastTranscript() {
        if let e = store.newest { Output.copyToClipboard(e.displayText) }
    }

    // MARK: Learned-words toast

    private var toastBatch: UUID?

    func showLearnedToast(batchId: UUID, words: [String]) {
        guard !words.isEmpty else { return }
        toastBatch = batchId
        overlay.show(.learned(batchId: batchId, words: words))
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            var remaining = ToastTiming.timeout
            let step: Duration = .milliseconds(100)
            let deadline = ContinuousClock.now + ToastTiming.safetyHide
            while remaining > .zero, ContinuousClock.now < deadline {
                try? await Task.sleep(for: step)
                guard !Task.isCancelled, let self else { return }
                if !self.overlay.model.toastPaused { remaining -= step }
            }
            guard !Task.isCancelled, let self, case .learned = self.overlay.model.state else { return }
            self.overlay.hide()
        }
    }

    private func keepLearned() {
        toastTask?.cancel()
        overlay.hide()
    }

    private func undoLearned() {
        guard let batch = toastBatch else { overlay.hide(); return }
        toastTask?.cancel()
        LearningCoordinator.shared.undo(batchId: batch)
        overlay.show(.undone)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: ToastTiming.undoneLinger)
            guard !Task.isCancelled else { return }
            self?.overlay.hide()
        }
    }
}
