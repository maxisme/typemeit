import AVFoundation
import Foundation

/// Audio behind history entries, kept when the "keep audio" setting is on so a
/// dictation can be played back next to its transcript. Files are AAC at
/// 16 kbps, 16 kHz mono: intelligible speech at roughly 120 KB a minute. A file
/// is named after its history entry's id and goes when the entry does.
enum RecordingArchive {
    static let directory = Store.directory.appendingPathComponent("Recordings", isDirectory: true)

    private static let queue = DispatchQueue(label: "it.typeme.typemeit.recording-archive", qos: .utility)

    static func url(for file: String) -> URL { directory.appendingPathComponent(file) }

    /// Encodes off the main thread; the pipeline does not wait for it.
    /// Returns the file name to store on the history entry.
    static func save(_ pcm: [Float], id: UUID) -> String {
        let file = "\(id.uuidString).m4a"
        queue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try write(pcm, to: url(for: file))
            } catch {
                Log.audio.error("Could not save recording: \(error.localizedDescription)")
            }
        }
        return file
    }

    static func delete(_ files: [String]) {
        guard !files.isEmpty else { return }
        queue.async {
            for file in files { try? FileManager.default.removeItem(at: url(for: file)) }
        }
    }

    static func deleteAll() {
        queue.async { try? FileManager.default.removeItem(at: directory) }
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

/// Plays one history recording at a time from the history tab.
@MainActor
@Observable
final class RecordingPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = RecordingPlayer()

    private(set) var playing: UUID?
    private var player: AVAudioPlayer?

    func toggle(_ entry: HistoryEntry) {
        if playing == entry.id { stop(); return }
        stop()
        guard let file = entry.recordingFile else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: RecordingArchive.url(for: file))
            p.delegate = self
            p.play()
            player = p
            playing = entry.id
        } catch {
            Log.audio.error("Could not play recording: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
