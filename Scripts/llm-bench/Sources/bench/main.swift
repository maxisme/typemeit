import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: bench <repo-root> apple | <model.gguf> ..."); exit(64) }
let root = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let cases = try Cases.load(repoRoot: root)
let template = try Cases.template(repoRoot: root)
let templateFmt = Cases.withFormatting(template)

func bench(name: String, fileGB: Double?, loadSeconds: Double, run: (String, String) async throws -> LlamaEngine.Output) async throws -> Report {
    _ = try await run(Cases.instructions, template.replacingOccurrences(of: "${output}", with: "warm up"))
    let residentAfterLoad = Metrics.residentSizeBytes()
    let sampler = Metrics.Sampler()
    let cpu0 = Metrics.processCPUSeconds(), m0 = Metrics.machineTicks()
    var results: [CaseResult] = [], long: [CaseResult] = []
    for c in cases {
        let o = try await run(Cases.instructions, template.replacingOccurrences(of: "${output}", with: c.input))
        let ok = c.expected.contains { Cases.normalise(o.text) == Cases.normalise($0) }
        results.append(CaseResult(input: c.input, expected: c.expected, got: o.text, pass: ok, wallSeconds: o.promptSeconds + o.generateSeconds, promptTokens: o.promptTokens, outputTokens: o.outputTokens,
                                  promptTokensPerSecond: o.promptSeconds > 0 ? Double(o.promptTokens) / o.promptSeconds : 0, generationTokensPerSecond: o.generateSeconds > 0 ? Double(o.outputTokens) / o.generateSeconds : 0))
        print("  \(ok ? "PASS" : "FAIL")  \(String(format: "%.2fs", o.promptSeconds + o.generateSeconds))  \(c.input)")
        if !ok { print("        expected: \(c.expected.joined(separator: "\n              or: "))\n        got:      \(o.text)") }
    }
    for c in Cases.long {
        let s = c.input
        let o = try await run(Cases.instructions, templateFmt.replacingOccurrences(of: "${output}", with: s))
        let ok = c.expected.contains { Cases.normaliseLayout(o.text) == Cases.normaliseLayout($0) }
        long.append(CaseResult(input: s, expected: c.expected, got: o.text, pass: ok, wallSeconds: o.promptSeconds + o.generateSeconds, promptTokens: o.promptTokens, outputTokens: o.outputTokens,
                               promptTokensPerSecond: o.promptSeconds > 0 ? Double(o.promptTokens) / o.promptSeconds : 0, generationTokensPerSecond: o.generateSeconds > 0 ? Double(o.outputTokens) / o.generateSeconds : 0))
        print("  \(ok ? "PASS" : "FAIL")  \(String(format: "%.2fs", o.promptSeconds + o.generateSeconds))  long: \(s.split(separator: " ").count) words in, \(o.text.split(separator: " ").count) out, \(o.text.contains("\n") ? "has line breaks" : "single block")")
        print("        " + o.text.replacingOccurrences(of: "\n", with: "\n        "))
    }
    let cpu1 = Metrics.processCPUSeconds(), m1 = Metrics.machineTicks()
    let peak = sampler.stop()
    let passed = results.filter { $0.pass == true }.count
    let longPassed = long.filter { $0.pass == true }.count
    let summary = Summary(
        engine: name, fileGB: fileGB, loadSeconds: (loadSeconds * 100).rounded() / 100,
        residentAfterLoadGB: (Double(residentAfterLoad) / 1e7).rounded() / 100, peakResidentGB: (Double(peak) / 1e7).rounded() / 100,
        footprintGB: (Double(Metrics.residentBytes()) / 1e7).rounded() / 100,
        processCPUSeconds: ((cpu1 - cpu0) * 10).rounded() / 10,
        machineCPUBusyPercent: m1.total > m0.total ? (Double(m1.busy - m0.busy) / Double(m1.total - m0.total) * 1000).rounded() / 10 : 0,
        passed: "\(passed)/\(cases.count)", longPassed: "\(longPassed)/\(long.count)",
        meanWallSeconds: (results.map(\.wallSeconds).reduce(0, +) / Double(results.count) * 100).rounded() / 100,
        meanGenerationTokensPerSecond: (results.map(\.generationTokensPerSecond).reduce(0, +) / Double(results.count)).rounded(),
        longMeanWallSeconds: (long.map(\.wallSeconds).reduce(0, +) / Double(long.count) * 100).rounded() / 100)
    return Report(summary: summary, cases: results, long: long)
}

let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
for arg in args[2...] {
    let report: Report
    if arg == "apple" {
        print("== Apple Intelligence")
        let e = AppleEngine()
        report = try await bench(name: "Apple Intelligence", fileGB: nil, loadSeconds: 0) { try await e.run(system: $0, user: $1) }
    } else {
        print("== \(URL(fileURLWithPath: arg).lastPathComponent)")
        let e = try LlamaEngine(path: arg)
        let size = (try? FileManager.default.attributesOfItem(atPath: arg)[.size] as? Int).map { (Double($0) / 1e7).rounded() / 100 }
        report = try await bench(name: URL(fileURLWithPath: arg).lastPathComponent, fileGB: size, loadSeconds: e.loadSeconds) { try e.run(system: $0, user: $1) }
    }
    let name = report.summary.engine.replacingOccurrences(of: " ", with: "-")
    try encoder.encode(report).write(to: outDir.appendingPathComponent("result-\(name).json"))
    print(String(decoding: try encoder.encode(report.summary), as: UTF8.self))
}
