import CryptoKit
import Foundation

/// One report about a dictation, sent from the history tab to typeme.it. It
/// carries what the engine heard, what was typed, the settings in force, the
/// app and machine, and the audio when the entry kept it and the user left it
/// in. Nothing is sent until the user presses send.
struct FeedbackReport: Encodable, Equatable {
    struct App: Encodable, Equatable {
        var version: String
        var build: String
        var macos: String
        var chip: String?
        var appleIntelligence: String
        var model: String
    }

    struct Dictation: Encodable, Equatable {
        var id: String
        var at: String
        var transcript: String
        var postProcessed: String?
        var postProcessRequested: Bool
        var edited: String?
        var durationMs: Int?
        var transcribeMs: Int?
        var postProcessMs: Int?
        var dictionaryFixes: Int
        var appId: String?
        var appName: String?
        var windowTitle: String?
    }

    var issue: String
    var previousId: String?
    var app: App
    var dictation: Dictation
    /// Every toggle and choice in settings, keyed by its UserDefaults name.
    /// Lists are sent as counts: the custom words themselves are not part of a
    /// report.
    var settings: [String: SettingValue]
    /// Base64 of the entry's m4a file.
    var audio: String?

    enum SettingValue: Encodable, Equatable {
        case bool(Bool), int(Int), string(String)
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .bool(let v): try c.encode(v)
            case .int(let v): try c.encode(v)
            case .string(let v): try c.encode(v)
            }
        }
    }

    static func dictation(_ e: HistoryEntry) -> Dictation {
        Dictation(
            id: e.id.uuidString, at: e.timestamp.ISO8601Format(), transcript: e.transcript,
            postProcessed: e.postProcessed, postProcessRequested: e.postProcessRequested, edited: e.edited,
            durationMs: e.durationMs, transcribeMs: e.transcribeMs, postProcessMs: e.postProcessMs,
            dictionaryFixes: e.dictionaryFixes, appId: e.appId, appName: e.appName, windowTitle: e.windowTitle)
    }

    @MainActor
    static func settings(_ s: Settings, learnedWords: Int) -> [String: SettingValue] {
        [
            "muteWhileRecording": .bool(s.muteWhileRecording),
            "audioFeedback": .bool(s.audioFeedback),
            "copyPromptEnabled": .bool(s.copyPromptEnabled),
            "postProcessingEnabled": .bool(s.postProcessingEnabled),
            "customWords": .int(s.customWords.count),
            "learnedWords": .int(learnedWords),
            "learnFromCorrections": .bool(s.learnFromCorrections),
            "appendTrailingSpace": .bool(s.appendTrailingSpace),
            "autoSubmit": .bool(s.autoSubmit),
            "autoSubmitKey": .string(s.autoSubmitKey.rawValue),
            "historyLimit": .int(s.historyLimit),
            "keepRecordings": .bool(s.keepRecordings),
            "askBeforeUpdating": .bool(s.askBeforeUpdating),
            "launchAtLogin": .bool(s.launchAtLogin),
            "showDockIcon": .bool(s.showDockIcon),
            "appearance": .string(s.appearance.rawValue),
            "cloudColorEnabled": .bool(s.cloudColorEnabled),
            "cloudColor": .string(s.cloudColor.rawValue),
            "cloudPosition": .string(s.cloudPosition.rawValue),
            "cloudMatchesBackdrop": .bool(s.cloudMatchesBackdrop),
            "screenContextEnabled": .bool(s.screenContextEnabled),
            "copyLastShortcut": .bool(s.copyLastShortcut != nil),
            "microphoneChosen": .bool(s.microphoneUID != nil),
        ]
    }

    @MainActor
    static func app() -> App {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return App(
            version: AppVersion.current,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            macos: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            chip: sysctlString("machdep.cpu.brand_string"),
            appleIntelligence: String(describing: PostProcessor.availability),
            model: ModelStore.fileName)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

/// Signs and posts reports. The key is compiled in from the build's
/// `FEEDBACK_KEY` setting as "id:hex"; a build without one cannot send, and
/// the sheet says so.
enum FeedbackClient {
    enum Failure: Error, Equatable {
        case noKey
        case status(Int)
        case transport(String)
        case tooLarge
    }

    static let endpoint = Fixed.websiteURL.appendingPathComponent("api/feedback")
    static let maxBodyBytes = 3 * 1024 * 1024

    static var key: (id: String, secret: SymmetricKey)? {
        parseKey(Bundle.main.object(forInfoDictionaryKey: "TMIFeedbackKey") as? String)
    }

    static func parseKey(_ spec: String?) -> (id: String, secret: SymmetricKey)? {
        guard let spec, let colon = spec.firstIndex(of: ":") else { return nil }
        let id = String(spec[..<colon])
        let hex = spec[spec.index(after: colon)...]
        guard !id.isEmpty, hex.count == 64, let bytes = Data(hex: String(hex)) else { return nil }
        return (id, SymmetricKey(data: bytes))
    }

    /// The headers the worker checks: the key id, the unix time, and an HMAC
    /// over "<time>.<sha256 of the body>".
    static func sign(_ body: Data, key: (id: String, secret: SymmetricKey), at time: Int) -> [String: String] {
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(time).\(digest)".utf8), using: key.secret)
        return [
            "X-Key-Id": key.id,
            "X-Timestamp": String(time),
            "X-Signature": mac.map { String(format: "%02x", $0) }.joined(),
        ]
    }

    static func encode(_ report: FeedbackReport) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(report)
    }

    /// Returns the report id the worker assigned.
    static func send(_ report: FeedbackReport) async throws -> String {
        guard let key else { throw Failure.noKey }
        let body = try encode(report)
        guard body.count <= maxBodyBytes else { throw Failure.tooLarge }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in sign(body, key: key, at: Int(Date().timeIntervalSince1970)) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Failure.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw Failure.status(status) }
        struct Reply: Decodable { var id: String }
        return try JSONDecoder().decode(Reply.self, from: data).id
    }
}

extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var out = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        self = out
    }
}
