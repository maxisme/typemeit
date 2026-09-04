import CryptoKit
import Foundation
import Observation

/// Downloads and locates the one speech model the app uses.
@MainActor
@Observable
final class ModelStore: NSObject, URLSessionDownloadDelegate {
    static let shared = ModelStore()

    nonisolated static let fileName = "parakeet-unified-en-0.6b-Q8_0.gguf"
    nonisolated static let expectedBytes: Int64 = 731_357_568
    nonisolated static let sha256 = "4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795"
    nonisolated static let primaryURL = URL(string: "https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf/resolve/7e948f21b7bdbac698d3318db9d350f1096f3b6c/parakeet-unified-en-0.6b-Q8_0.gguf")!
    nonisolated static let mirrorURL = URL(string: "https://blob.handy.computer/handy-computer/parakeet-unified-en-0.6b-gguf/7e948f21b7bdbac698d3318db9d350f1096f3b6c/parakeet-unified-en-0.6b-Q8_0.gguf")!

    nonisolated static let modelsDirectory = Store.directory.appendingPathComponent("models", isDirectory: true)
    nonisolated static let modelURL = modelsDirectory.appendingPathComponent(fileName)

    enum State: Equatable, Sendable {
        case missing
        case downloading(received: Int64, total: Int64)
        case verifying
        case failed(String)
        case installed
    }

    private(set) var state: State
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private var failures = 0
    @ObservationIgnored private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    private override init() {
        try? FileManager.default.createDirectory(at: ModelStore.modelsDirectory, withIntermediateDirectories: true)
        state = ModelStore.isInstalled ? .installed : .missing
        super.init()
    }

    nonisolated static var isInstalled: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let size = attrs[.size] as? Int64 else { return false }
        return size == expectedBytes
    }

    func download() {
        guard task == nil, state != .installed else { return }
        state = .downloading(received: 0, total: ModelStore.expectedBytes)
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
        } else {
            let url = failures >= 2 ? ModelStore.mirrorURL : ModelStore.primaryURL
            task = session.downloadTask(with: url)
        }
        task?.resume()
    }

    func cancel() {
        task?.cancel { [weak self] data in
            Task { @MainActor in
                self?.resumeData = data
                self?.task = nil
                self?.state = .missing
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            self.state = .downloading(received: totalBytesWritten, total: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : ModelStore.expectedBytes)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move out of the temporary location synchronously; it is deleted when this returns.
        let staging = ModelStore.modelsDirectory.appendingPathComponent("download.partial")
        try? FileManager.default.removeItem(at: staging)
        do { try FileManager.default.moveItem(at: location, to: staging) } catch {
            Task { @MainActor in self.fail("Could not save the download: \(error.localizedDescription)") }
            return
        }
        Task { @MainActor in
            self.state = .verifying
            let ok = await ModelStore.verify(staging)
            if ok {
                try? FileManager.default.removeItem(at: ModelStore.modelURL)
                do {
                    try FileManager.default.moveItem(at: staging, to: ModelStore.modelURL)
                    self.task = nil
                    self.state = .installed
                    Log.model.info("Model installed")
                } catch {
                    self.fail("Could not move the model into place: \(error.localizedDescription)")
                }
            } else {
                try? FileManager.default.removeItem(at: staging)
                self.fail("The downloaded file did not match its checksum.")
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }
        let resume = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            self.resumeData = resume
            self.fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        failures += 1
        task = nil
        state = .failed(message)
        Log.model.error("Model download failed: \(message)")
    }

    private nonisolated static func verify(_ url: URL) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return digest == sha256
        }.value
    }
}
