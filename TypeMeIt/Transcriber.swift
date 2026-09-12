import Foundation
import TranscribeCpp

/// transcribe.cpp with Metal. One model, one session, loaded on first use and
/// freed after five idle minutes. Sessions are single-threaded; the actor
/// guarantees one run at a time.
actor Transcriber {
    static let shared = Transcriber()

    private var model: OpaquePointer?
    private var session: OpaquePointer?
    private var unloadTask: Task<Void, Never>?
    private let abortFlag = AbortFlag()
    private var backendsReady = false

    final class AbortFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    enum Error: Swift.Error, LocalizedError {
        case status(String)
        case aborted
        var errorDescription: String? {
            switch self {
            case .status(let s): "Transcription failed: \(s)"
            case .aborted: "Transcription cancelled"
            }
        }
    }

    private init() {}

    private static func check(_ st: transcribe_status) throws {
        guard st != TRANSCRIBE_OK else { return }
        if st == TRANSCRIBE_ERR_ABORTED { throw Error.aborted }
        throw Error.status(String(cString: transcribe_status_string(Int32(st.rawValue))))
    }

    private func ensureLoaded() throws {
        if session != nil { return }
        if !backendsReady {
            transcribe_log_set({ level, msg, _ in
                guard let msg else { return }
                let text = String(cString: msg)
                switch level {
                case TRANSCRIBE_LOG_LEVEL_ERROR: Log.transcriber.error("\(text)")
                case TRANSCRIBE_LOG_LEVEL_WARN: Log.transcriber.warning("\(text)")
                default: break
                }
            }, nil)
            try Transcriber.check(transcribe_init_backends_default())
            backendsReady = true
        }
        let path = ModelStore.modelURL.path
        var lp = transcribe_model_load_params()
        transcribe_model_load_params_init(&lp)
        lp.backend = TRANSCRIBE_BACKEND_METAL
        var m: OpaquePointer?
        let started = ContinuousClock.now
        var st = transcribe_model_load_file(path, &lp, &m)
        if st == TRANSCRIBE_ERR_BACKEND {
            Log.transcriber.warning("Metal unavailable, loading on CPU")
            lp.backend = TRANSCRIBE_BACKEND_CPU
            st = transcribe_model_load_file(path, &lp, &m)
        }
        try Transcriber.check(st)
        var sp = transcribe_session_params()
        transcribe_session_params_init(&sp)
        var s: OpaquePointer?
        try Transcriber.check(transcribe_session_init(m, &sp, &s))
        model = m
        session = s
        let flag = abortFlag
        transcribe_set_abort_callback(s, { userInfo in
            guard let userInfo else { return false }
            return Unmanaged<AbortFlag>.fromOpaque(userInfo).takeUnretainedValue().get()
        }, Unmanaged.passUnretained(flag).toOpaque())
        let backend = m.map { String(cString: transcribe_model_backend($0)) } ?? "?"
        Log.transcriber.info("Model loaded on \(backend) in \(ContinuousClock.now - started)")
    }

    func preload() {
        do { try ensureLoaded() } catch { Log.transcriber.error("Preload failed: \(error.localizedDescription)") }
        scheduleUnload()
    }

    /// One word of a transcript with how sure the model was of it.
    struct Word: Sendable, Equatable {
        let text: String
        /// The lowest per-token probability among the word's tokens. Parakeet
        /// reports a joint-softmax probability per emitted token; the library
        /// calls it a confidence hint, not a calibrated probability. NaN when
        /// the model produced none.
        let confidence: Float
        let start: Duration
        let end: Duration
    }

    struct Transcript: Sendable {
        let text: String
        /// Empty when the model returned no word rows.
        let words: [Word]

        /// The text split on whitespace with confidence attached where the
        /// word rows line up with it one to one; otherwise every word is
        /// unknown, which the matcher treats as uncertain.
        var matcherWords: [CustomWordMatcher.Word] {
            let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == words.count, zip(parts, words).allSatisfy({ $0 == $1.text }) else {
                return parts.map { CustomWordMatcher.Word(text: $0, confidence: nil) }
            }
            return zip(parts, words).map { CustomWordMatcher.Word(text: $0, confidence: $1.confidence.isNaN ? nil : $1.confidence) }
        }
    }

    /// pcm: mono Float32 at 16 kHz.
    func transcribe(_ pcm: [Float]) throws -> String {
        try transcribeScored(pcm).text
    }

    func transcribeScored(_ pcm: [Float]) throws -> Transcript {
        unloadTask?.cancel()
        try ensureLoaded()
        abortFlag.set(false)
        var rp = transcribe_run_params()
        transcribe_run_params_init(&rp)
        let started = ContinuousClock.now
        let st = pcm.withUnsafeBufferPointer { transcribe_run(session, $0.baseAddress, Int32(pcm.count), &rp) }
        defer { scheduleUnload() }
        try Transcriber.check(st)
        let text = String(cString: transcribe_full_text(session))
        Log.transcriber.info("Transcribed \(pcm.count / 16000) s of audio in \(ContinuousClock.now - started)")
        return Transcript(text: text, words: Transcriber.words(of: session))
    }

    /// Word rows with the confidence folded in from their token rows. The
    /// library says to read the returned timestamp kind rather than assume
    /// rows exist: a family without word alignment returns no word rows.
    static func words(of session: OpaquePointer?) -> [Word] {
        guard transcribe_returned_timestamp_kind(session).rawValue >= TRANSCRIBE_TIMESTAMPS_WORD.rawValue else { return [] }
        let n = Int(transcribe_n_words(session))
        var words: [Word] = []
        words.reserveCapacity(n)
        for i in 0..<n {
            var w = transcribe_word()
            transcribe_word_init(&w)
            guard transcribe_get_word(session, Int32(i), &w) == TRANSCRIBE_OK, let text = w.text else { continue }
            var confidence = Float.nan
            for t in w.first_token..<(w.first_token + w.n_tokens) {
                var tok = transcribe_token()
                transcribe_token_init(&tok)
                guard transcribe_get_token(session, t, &tok) == TRANSCRIBE_OK, tok.text != nil, !tok.p.isNaN else { continue }
                confidence = confidence.isNaN ? tok.p : min(confidence, tok.p)
            }
            words.append(Word(text: String(cString: text).trimmingCharacters(in: .whitespaces), confidence: confidence,
                              start: .milliseconds(w.t0_ms), end: .milliseconds(w.t1_ms)))
        }
        return words
    }

    nonisolated func cancel() { abortFlag.set(true) }

    private func scheduleUnload() {
        unloadTask?.cancel()
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: Fixed.modelUnloadIdle)
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }

    func unload() {
        guard session != nil || model != nil else { return }
        transcribe_session_free(session)
        transcribe_model_free(model)
        session = nil
        model = nil
        Log.transcriber.info("Model unloaded after idle")
    }
}
