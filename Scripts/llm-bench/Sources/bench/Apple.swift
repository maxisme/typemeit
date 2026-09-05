import Foundation
import FoundationModels

@Generable struct CleanedTranscript: Sendable { let cleanedText: String }

/// The app's own path: Foundation Models, guided generation, greedy sampling.
struct AppleEngine {
    let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    func run(system: String, user: String) async throws -> LlamaEngine.Output {
        let session = LanguageModelSession(model: model, instructions: system)
        let t0 = Date()
        let r = try await session.respond(to: user, generating: CleanedTranscript.self, options: GenerationOptions(sampling: .greedy))
        let dt = Date().timeIntervalSince(t0)
        // Foundation Models does not expose token counts, so tokens are estimated at 1.3 a word.
        let est = { (s: String) in Int(Double(s.split(separator: " ").count) * 1.3) }
        return LlamaEngine.Output(text: r.content.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines), promptTokens: est(user), outputTokens: est(r.content.cleanedText), promptSeconds: 0, generateSeconds: dt)
    }
}
