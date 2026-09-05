import AVFoundation
import Foundation

/// Dev builds keep every recording on disk so a bad transcript can be replayed
/// against the audio that produced it. Files are AAC at 16 kbps, 16 kHz mono:
/// intelligible speech at roughly 120 KB a minute. Release builds write nothing.
enum RecordingArchive {
    static let enabled = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    static let directory = Store.directory.appendingPathComponent("Recordings", isDirectory: true)

    private static let queue = DispatchQueue(label: "it.typeme.typemeit.recording-archive", qos: .utility)
    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    /// Encodes off the main thread; the pipeline does not wait for it.
    /// `note` is appended to the file name, e.g. "discarded".
    static func save(_ pcm: [Float], recordedAt: Date, note: String? = nil) {
        guard enabled, !pcm.isEmpty else { return }
        var name = nameFormatter.string(from: recordedAt)
        if let note { name += " \(note)" }
        let url = directory.appendingPathComponent(name).appendingPathExtension("m4a")
        queue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try write(pcm, to: url)
                Log.audio.info("Archived recording to \(url.path)")
            } catch {
                Log.audio.error("Could not archive recording: \(error.localizedDescription)")
            }
        }
    }

    private static func write(_ pcm: [Float], to url: URL) throws {
        let format = AudioCapture.targetFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 16_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw NSError(domain: "Type Me It.Audio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not allocate an audio buffer"])
        }
        pcm.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: pcm.count) }
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        try file.write(from: buffer)
    }
}
