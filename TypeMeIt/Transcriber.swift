import Foundation
import TranscribeCpp

/// transcribe.cpp with Metal. One model, one session, loaded at launch (or on
/// first use) and freed after thirty idle minutes. Sessions are single-threaded;
/// the actor guarantees one run at a time.
actor Transcriber {
    static let shared = Transcriber()

    private var model: OpaquePointer?
    private var session: OpaquePointer?
    private var unloadTask: Task<Void, Never>?
    private let abortFlag = AbortFlag()
    private var backendsReady = false
    private var warmedUp = false

    var isLoaded: Bool { session != nil }

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
        Log.transcriber.info("Model loaded on \(backend, privacy: .public) in \(ContinuousClock.now - started, privacy: .public)")
    }

    /// Loads the model and runs one second of silence through it, so the first
    /// real dictation does not pay for the Metal pipeline warm-up (measured at
    /// two to five times the steady-state run time).
    func preload() {
        do {
            try ensureLoaded()
            try warmUp()
        } catch { Log.transcriber.error("Preload failed: \(error.localizedDescription)") }
        scheduleUnload()
    }

    /// Loads without the warm-up run. The pipeline calls this when a recording
    /// is already waiting, so the overlay can say what it is waiting for.
    func load() throws {
        unloadTask?.cancel()
        try ensureLoaded()
    }

    private func warmUp() throws {
        guard !warmedUp else { return }
        let silence = [Float](repeating: 0, count: 16000)
        var rp = transcribe_run_params()
        transcribe_run_params_init(&rp)
        abortFlag.set(false)
        let started = ContinuousClock.now
        let st = silence.withUnsafeBufferPointer { transcribe_run(session, $0.baseAddress, Int32(silence.count), &rp) }
        try Transcriber.check(st)
        warmedUp = true
        Log.transcriber.info("Warm-up run took \(ContinuousClock.now - started, privacy: .public)")
    }

    /// pcm: mono Float32 at 16 kHz.
    func transcribe(_ pcm: [Float]) throws -> String {
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
        Log.transcriber.info("Transcribed \(pcm.count / 16000, privacy: .public) s of audio in \(ContinuousClock.now - started, privacy: .public)")
        return text
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
        warmedUp = false
        Log.transcriber.info("Model unloaded after idle")
    }
}
