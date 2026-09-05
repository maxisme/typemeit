import AVFoundation
import CoreAudio
import Foundation

/// AVAudioEngine input, converted to 16 kHz mono Float32. The tap runs on the
/// audio thread, so the buffer is guarded by a lock.
final class AudioCapture: @unchecked Sendable {
    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var recording = false
    private var converter: AVAudioConverter?
    private var engineRunning = false
    private var configObserver: NSObjectProtocol?

    /// Level in 0...1 for the pill, published at most 30 times a second.
    var onLevel: (@Sendable (Float) -> Void)?
    var onFirstBuffer: (@Sendable () -> Void)?
    private var lastLevelAt: TimeInterval = 0
    /// Loudest sample since the last level report, so a consonant that lands
    /// between reports still reaches the puff.
    private var peakSinceReport: Float = 0
    private var firstBufferReported = false

    init() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Log.audio.info("Audio engine configuration changed; restarting")
            self.restartIfRunning()
        }
    }

    // MARK: Device selection

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), uidPtr, &size, &deviceID)
        }
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private func applyInputDevice(uid: String?) {
        guard let uid, var deviceID = AudioCapture.deviceID(forUID: uid), let unit = engine.inputNode.audioUnit else { return }
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr { Log.audio.error("Could not select input device \(uid): \(status)") }
    }

    // MARK: Engine

    private func ensureEngine(uid: String?) throws {
        guard !engineRunning else { return }
        applyInputDevice(uid: uid)
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw NSError(domain: "Type Me It.Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio input device"])
        }
        converter = AVAudioConverter(from: inFormat, to: AudioCapture.targetFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        try engine.start()
        engineRunning = true
    }

    private func stopEngine() {
        guard engineRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engineRunning = false
    }

    private var lastUID: String?
    private var alwaysOn = false

    private func restartIfRunning() {
        guard engineRunning else { return }
        stopEngine()
        try? ensureEngine(uid: lastUID)
    }

    /// Opens the engine ahead of time (always-on microphone).
    func warmUp(uid: String?) {
        lastUID = uid
        alwaysOn = true
        try? ensureEngine(uid: uid)
    }

    func coolDown() {
        alwaysOn = false
        if !recording { stopEngine() }
    }

    func start(uid: String?) throws {
        lastUID = uid
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        recording = true
        firstBufferReported = false
        peakSinceReport = 0
        lock.unlock()
        try ensureEngine(uid: uid)
    }

    /// Returns 16 kHz mono Float32 samples.
    func stop() -> [Float] {
        lock.lock()
        recording = false
        let out = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        if !alwaysOn { stopEngine() }
        return out
    }

    func cancel() {
        lock.lock()
        recording = false
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        if !alwaysOn { stopEngine() }
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let isRecording = recording
        lock.unlock()
        guard isRecording, let converter else { return }

        let ratio = AudioCapture.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: AudioCapture.targetFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { Log.audio.error("Conversion failed: \(error.localizedDescription)"); return }
        let n = Int(out.frameLength)
        guard n > 0, let data = out.floatChannelData?[0] else { return }
        var peak: Float = 0
        for i in 0..<n { peak = max(peak, abs(data[i])) }
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: data, count: n))
        let report = !firstBufferReported
        firstBufferReported = true
        lock.unlock()
        if report { onFirstBuffer?() }

        let now = Date().timeIntervalSinceReferenceDate
        peakSinceReport = max(peakSinceReport, peak)
        if now - lastLevelAt >= 1.0 / 30.0 {
            lastLevelAt = now
            let db = 20 * log10(max(peakSinceReport * 0.8, 1e-6))
            peakSinceReport = 0
            let level = min(1, max(0, (db + 52) / 50))
            onLevel?(level)
        }
    }

    // MARK: Devices for the settings UI

    struct Device: Identifiable, Hashable, Sendable {
        var id: String  // uniqueID
        var name: String
    }

    static func inputDevices() -> [Device] {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        return session.devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func peak(_ pcm: [Float]) -> Float {
        var p: Float = 0
        for v in pcm { let a = abs(v); if a > p { p = a } }
        return p
    }
}
