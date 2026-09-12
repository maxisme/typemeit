import AVFoundation
import Foundation

// For every history entry with a recording, transcribes it again and prints
// each word with its confidence. Words the user later corrected (learned
// words, keyed by history id) are marked, and the summary compares the two
// populations: if corrected words score clearly lower, confidence can gate
// the custom-word matcher. Usage: probe [max entries] [--all]

struct Entry: Decodable { let id: String; let transcript: String; let recordingFile: String?; let timestamp: String }
struct Learned: Decodable { let heard: String; let historyId: String; let undone: Bool }

let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TypeMeIt")
let limit = CommandLine.arguments.dropFirst().compactMap(Int.init).first ?? 80
let showAll = CommandLine.arguments.contains("--all")

let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: support.appendingPathComponent("history.json")))
let learned = try JSONDecoder().decode([Learned].self, from: Data(contentsOf: support.appendingPathComponent("learned-words.json")))
var heardByHistory: [String: [String]] = [:]
for l in learned where !l.undone { heardByHistory[l.historyId, default: []].append(l.heard.lowercased()) }

func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

func pcm(of url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: inBuf)
    if file.processingFormat.sampleRate == 16000 && file.processingFormat.channelCount == 1 {
        return Array(UnsafeBufferPointer(start: inBuf.floatChannelData![0], count: Int(inBuf.frameLength)))
    }
    let converter = AVAudioConverter(from: file.processingFormat, to: target)!
    let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * 16000 / file.processingFormat.sampleRate) + 1024
    let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCap)!
    var fed = false
    var err: NSError?
    converter.convert(to: outBuf, error: &err) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true; status.pointee = .haveData; return inBuf
    }
    if let err { throw err }
    return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
}

let candidates = entries.filter { $0.recordingFile != nil }.sorted { $0.timestamp > $1.timestamp }
let picked = showAll ? candidates : Array(candidates.prefix(limit))
var corrected: [Float] = [], other: [Float] = []
var missingConfidence = 0

for e in picked {
    let url = support.appendingPathComponent("Recordings/\(e.recordingFile!)")
    guard FileManager.default.fileExists(atPath: url.path) else { continue }
    let t: Transcriber.Transcript
    do { t = try await Transcriber.shared.transcribeScored(try pcm(of: url)) } catch { print("!! \(e.id): \(error)"); continue }
    let heard = heardByHistory[e.id] ?? []
    let heardKeys = Set(heard.flatMap { $0.split(separator: " ").map { key(String($0)) } })
    print("\n== \(e.timestamp)  \(e.id.prefix(8))")
    print("   stored: \(e.transcript)")
    print("   now:    \(t.text)")
    if !heard.isEmpty { print("   corrected later: \(heard.joined(separator: " | "))") }
    var line = "   "
    for w in t.words {
        if w.confidence.isNaN { missingConfidence += 1 }
        let wrong = heardKeys.contains(key(w.text))
        if wrong { corrected.append(w.confidence) } else { other.append(w.confidence) }
        line += "\(w.text)\(wrong ? "*" : "")[\(String(format: "%.2f", w.confidence))] "
    }
    print(line)
}

func stats(_ xs: [Float]) -> String {
    let s = xs.filter { !$0.isNaN }.sorted()
    guard !s.isEmpty else { return "none" }
    func q(_ p: Double) -> Float { s[min(s.count - 1, Int(Double(s.count) * p))] }
    let below = { (t: Float) in s.filter { $0 < t }.count }
    return String(format: "n=%d  p10=%.2f  median=%.2f  p90=%.2f  <0.5: %d  <0.8: %d", s.count, q(0.1), q(0.5), q(0.9), below(0.5), below(0.8))
}
print("\n=== summary over \(picked.count) recordings")
print("words later corrected:  \(stats(corrected))")
print("all other words:        \(stats(other))")
if missingConfidence > 0 { print("words with no confidence: \(missingConfidence)") }
// ggml asserts at exit when the Metal device is torn down under a live session.
await Transcriber.shared.unload()
