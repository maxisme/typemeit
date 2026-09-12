import Foundation

// The two app types Transcriber reaches for, reduced to what it reads.
enum ModelStore {
    static let modelURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TypeMeIt/models/parakeet-unified-en-0.6b-Q8_0.gguf")
}

enum Fixed {
    static let modelUnloadIdle: Duration = .seconds(3600)
}
