import CryptoKit
import Foundation
import Testing
@testable import TypeMeIt

struct FeedbackTests {
    @Test func keySpecParses() {
        let key = FeedbackClient.parseKey("1:" + String(repeating: "0b", count: 32))
        #expect(key?.id == "1")
        #expect(key?.secret.bitCount == 256)
        #expect(FeedbackClient.parseKey("1:abc") == nil)
        #expect(FeedbackClient.parseKey(":" + String(repeating: "0b", count: 32)) == nil)
        #expect(FeedbackClient.parseKey(nil) == nil)
        #expect(FeedbackClient.parseKey("") == nil)
    }

    /// The same vector feedback.test.mjs computes: the worker and the app must
    /// agree byte for byte.
    @Test func signatureMatchesTheWorker() throws {
        let key = try #require(FeedbackClient.parseKey("1:" + String(repeating: "0b", count: 32)))
        let body = Data("{\"issue\":\"x\"}".utf8)
        let headers = FeedbackClient.sign(body, key: key, at: 1_000_000)
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let expected = HMAC<SHA256>.authenticationCode(for: Data("1000000.\(digest)".utf8), using: key.secret)
            .map { String(format: "%02x", $0) }.joined()
        #expect(headers == ["X-Key-Id": "1", "X-Timestamp": "1000000", "X-Signature": expected])
    }

    @Test func bodyIsStableAcrossEncodes() throws {
        let entry = HistoryEntry(timestamp: Date(timeIntervalSince1970: 0), transcript: "hello there", postProcessed: "Hello there",
                                 postProcessRequested: true, durationMs: 900, transcribeMs: 120, appName: "Slack", dictionaryFixes: 0)
        let report = FeedbackReport(
            issue: "wrong word", previousId: nil,
            app: .init(version: "0.6.0", build: "12", macos: "26.0.0", chip: "Apple M3", appleIntelligence: "available", model: "m.gguf"),
            dictation: FeedbackReport.dictation(entry),
            settings: ["postProcessingEnabled": .bool(true), "historyLimit": .int(500), "appearance": .string("system")],
            audio: nil)
        let a = try FeedbackClient.encode(report)
        let b = try FeedbackClient.encode(report)
        #expect(a == b)
        let decoded = try #require(JSONSerialization.jsonObject(with: a) as? [String: Any])
        let dictation = try #require(decoded["dictation"] as? [String: Any])
        #expect(dictation["id"] as? String == entry.id.uuidString)
        #expect(dictation["at"] as? String == "1970-01-01T00:00:00Z")
        #expect(dictation["transcript"] as? String == "hello there")
        #expect(decoded["audio"] == nil)
        let settings = try #require(decoded["settings"] as? [String: Any])
        #expect(settings["historyLimit"] as? Int == 500)
    }
}
