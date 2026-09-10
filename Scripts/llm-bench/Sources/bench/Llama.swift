import CLlama
import Foundation

/// One loaded GGUF model with a context, greedy sampling and a JSON grammar
/// that pins the output to `{"cleanedText": "..."}`, matching the app's guided
/// generation into one field.
final class LlamaEngine {
    struct Output { var text: String; var promptTokens: Int; var outputTokens: Int; var promptSeconds: Double; var generateSeconds: Double }

    private let model: OpaquePointer
    private let ctx: OpaquePointer
    private let vocab: OpaquePointer
    private let chatTemplate: String?
    private let addsEmptyThink: Bool
    let loadSeconds: Double

    private static let grammar = #"""
    root ::= "{" ws "\"cleanedText\"" ws ":" ws string ws "}"
    string ::= "\"" ( [^"\\\x7F\x00-\x1F] | "\\" (["\\bfnrt] | "u" [0-9a-fA-F]{4}) )* "\""
    ws ::= [ \t\n]*
    """#

    init(path: String) throws {
        llama_backend_init()
        llama_log_set({ _, _, _ in }, nil)
        let t0 = Date()
        var mp = llama_model_default_params()
        mp.n_gpu_layers = 99
        guard let m = llama_model_load_from_file(path, mp) else { throw NSError(domain: "bench", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load \(path)"]) }
        var cp = llama_context_default_params()
        cp.n_ctx = 4096
        cp.n_batch = 1024
        guard let c = llama_init_from_model(m, cp) else { throw NSError(domain: "bench", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create a context"]) }
        model = m; ctx = c; vocab = llama_model_get_vocab(m)
        chatTemplate = llama_model_chat_template(m, nil).map { String(cString: $0) }
        // Qwen's template ends thinking with an empty think block when thinking is off.
        addsEmptyThink = chatTemplate?.contains("<think>") == true
        loadSeconds = Date().timeIntervalSince(t0)
    }

    deinit { llama_free(ctx); llama_model_free(model) }

    private func prompt(system: String, user: String) -> String {
        var messages = [llama_chat_message(role: strdup("system"), content: strdup(system)), llama_chat_message(role: strdup("user"), content: strdup(user))]
        defer { for m in messages { free(UnsafeMutablePointer(mutating: m.role)); free(UnsafeMutablePointer(mutating: m.content)) } }
        var buf = [CChar](repeating: 0, count: 32_768)
        let n = llama_chat_apply_template(chatTemplate, &messages, messages.count, true, &buf, Int32(buf.count))
        var out = n > 0 ? String(cString: Array(buf[0..<Int(n)]) + [0]) : system + "\n\n" + user + "\n"
        if addsEmptyThink { out += "<think>\n\n</think>\n\n" }
        return out
    }

    func run(system: String, user: String, maxTokens: Int32 = 600) throws -> Output {
        llama_memory_clear(llama_get_memory(ctx), true)
        let text = prompt(system: system, user: user)
        var tokens = [llama_token](repeating: 0, count: text.utf8.count + 16)
        let n = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard n > 0 else { throw NSError(domain: "bench", code: 3, userInfo: [NSLocalizedDescriptionKey: "Tokenize failed"]) }
        tokens.removeLast(tokens.count - Int(n))

        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(chain) }
        if ProcessInfo.processInfo.environment["BENCH_NO_GRAMMAR"] == nil {
            llama_sampler_chain_add(chain, llama_sampler_init_grammar(vocab, LlamaEngine.grammar, "root"))
        }
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())

        let t0 = Date()
        var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
        guard llama_decode(ctx, batch) == 0 else { throw NSError(domain: "bench", code: 4, userInfo: [NSLocalizedDescriptionKey: "Prompt decode failed"]) }
        llama_synchronize(ctx)  // decode returns before the GPU finishes; without this the prompt cost lands in generation time
        let t1 = Date()

        var out = [UInt8]()
        var produced = 0
        var piece = [CChar](repeating: 0, count: 256)
        while produced < maxTokens {
            var tok = llama_sampler_sample(chain, ctx, -1)
            if llama_vocab_is_eog(vocab, tok) { break }
            let len = llama_token_to_piece(vocab, tok, &piece, Int32(piece.count), 0, true)
            if len > 0 { out.append(contentsOf: piece[0..<Int(len)].map { UInt8(bitPattern: $0) }) }
            produced += 1
            batch = llama_batch_get_one(&tok, 1)
            guard llama_decode(ctx, batch) == 0 else { break }
        }
        let t2 = Date()
        var result = String(decoding: out, as: UTF8.self)
        if let data = result.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let s = obj["cleanedText"] as? String { result = s }
        return Output(text: result.trimmingCharacters(in: .whitespacesAndNewlines), promptTokens: tokens.count, outputTokens: produced, promptSeconds: t1.timeIntervalSince(t0), generateSeconds: t2.timeIntervalSince(t1))
    }
}
