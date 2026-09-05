# On-device alternatives to Apple Intelligence for transcript cleanup

Type Me It cleans transcripts with Apple's on-device foundation model through the
Foundation Models framework (`PostProcessor.swift`). This note records what else
could run the same job on the user's Mac, what it would cost in time, memory and
power, and what the current setup gives up. Written September 2026.

## What Apple Intelligence gives us today

- A roughly 3-billion-parameter model, quantised to 2 bits per weight, running in
  a system process rather than ours. Apple does not say which silicon blocks it
  uses. [Apple ML Research, 2025 updates][apple-2025]
- No download, no model files to version, and memory that the system owns and
  reclaims.
- Guided generation into a single `@Generable` field plus greedy sampling, which
  is what keeps the model editing rather than answering.
- Requirements: a Mac with Apple silicon, 7 GB free storage and macOS 15.1 or
  later for Apple Intelligence itself. [Apple Support][apple-req] The Foundation
  Models framework the app uses arrived in macOS 26, so the effective floor is
  macOS 26 on any Apple silicon Mac.
- A 4,096-token context window per session shared between instructions, prompt
  and output. Our template is about 400 tokens, so a transcript above roughly
  1,500 words cannot be cleaned in one call. [Apple Developer Forums][ctx]

Observed limit: with the September 2026 prompt including a mishearing rule, the
model still returned "Alexa set time up for half an hour" unchanged. Small models
follow "preserve word order" more readily than "fix what was meant".

## Runtimes we could embed

| Runtime | Shape | Notes |
|---|---|---|
| [llama.cpp][llamacpp] | C library, GGUF models, Metal backend | Most mature. Ships a Swift package and a SwiftUI example. Grammar-constrained output can replace guided generation. Would sit next to the existing `TranscribeCpp` package. |
| [MLX Swift LM][mlx] | Swift package from Apple's ml-explore, MIT | Swift-native, fast on Apple silicon, models from Hugging Face in MLX format. Younger than llama.cpp and a larger dependency. |
| Core ML | Convert once, ship a `.mlpackage` | Can use the Neural Engine. Conversion is slow to iterate and unnecessary for a single cleanup prompt. |
| Ollama / LM Studio | Separate daemon on localhost | Cannot be assumed installed. Power-user option only. |

## Models in the useful size range

All of the following are Apache 2.0 unless noted, so redistribution inside the
app is not a licensing question.

| Model | Sizes | Notes |
|---|---|---|
| [Qwen3.5 Small][qwen35] (March 2026) | 0.8B, 2B, 4B, 9B | Current Qwen line. Thinking and non-thinking modes; thinking must be turned off for cleanup or latency doubles. |
| [Qwen3][qwen3-4b] (2025) | 1.7B, 4B | Predecessor. Same `enable_thinking=False` switch or `/no_think` in the prompt. |
| [Gemma 4][gemma4] (April 2026) | E2B (~2.3B effective), E4B (~4.5B effective), 26B MoE, 31B | First Gemma under Apache 2.0. Gemma 3 used Google's custom terms, which is why it was less attractive. [Google][gemma4-blog] |
| Llama 3.2 | 1B, 3B | Llama licence, not Apache. Widely quantised but now dated. |

The models to try first are Qwen3.5 2B or 4B and Gemma 4 E2B or E4B. A 2B-class
model is the practical ceiling on an 8 GB Mac; a 4B-class model is fine on 16 GB.

## Speed

Inference on Apple silicon is bound by memory bandwidth, so generation speed
scales with the chip tier more than the generation. Measured 7B Q4_0 figures
from the llama.cpp benchmark thread: [llama.cpp discussion #4167][bench]

| Chip | Bandwidth GB/s | Prompt tok/s | Generation tok/s |
|---|---|---|---|
| M1 | 68 | 108 | 14 |
| M2 | 100 | 180 | 22 |
| M4 | 120 | 221 | 24 |
| M1 Pro | 200 | 266 | 36 |
| M4 Pro | 273 | 440 | 51 |
| M2 Max | 400 | 671 | 66 |
| M4 Max | 546 | 886 | 83 |

A 4B model runs about 1.7 times faster than these 7B numbers and a 2B model
about 3 times faster, since generation is proportional to bytes read per token.

What that means for a cleanup, where output length roughly equals input length:

| Transcript | 2B on M2 | 4B on M2 | 4B on M4 Pro | Apple Intelligence |
|---|---|---|---|---|
| 30 words (~40 tokens out) | under 1 s | ~1 s | under 1 s | ~1 s |
| 300 words (~400 tokens out) | ~6 s | ~11 s | ~5 s | comparable to a 4B |

Apple's model generates the whole transcript token by token as well, so for long
dictations no engine choice makes cleanup fast. The levers that would are
streaming the cleaned text as it arrives, splitting at sentence boundaries and
cleaning chunks in parallel, or skipping the model above a length threshold.

Cold load of a 2.5 GB model takes one to three seconds. The idle unload timer
used for the speech model (`Fixed.modelUnloadIdle`) would apply.

## Memory and power

| Model | Q4 weights | Working memory at ~1,200 tokens | Resident total |
|---|---|---|---|
| Apple Intelligence | 0 in our process | 0 in our process | system-owned |
| 2B class | ~1.3 GB | ~0.2 GB | ~1.5 GB |
| 4B class | ~2.5 GB | ~0.3 GB | ~2.8 GB |
| 9B class | ~5 GB | ~0.5 GB | ~5.5 GB |

The speech model is resident during a dictation as well, so a 4B cleanup model
puts the app at about 4 GB while working. This is the strongest argument for
keeping Apple Intelligence as the default.

With Metal, generation occupies the GPU and one CPU core. A ten-second job will
not spin up fans on a MacBook Pro; a fanless Air gets warm after a run of long
dictations. A model in our process draws more power than Apple's, which runs in
a system process tuned for the hardware. CPU-only inference is three to five
times slower and should not ship.

## Recommendation

Keep Apple Intelligence as the default. If cleanup quality or Mac coverage
becomes a problem, add llama.cpp as an optional engine behind a setting with
Qwen3.5 4B or Gemma 4 E4B as the model, thinking disabled, downloaded and staged
through the existing `ModelStore` flow. It covers Macs below macOS 26, gives us
control over the prompt format and sampling, and on a 16 GB Mac matches Apple's
speed for a sentence. The costs are a 2 to 3 GB download and 3 GB of resident
memory while loaded.

[apple-2025]: https://machinelearning.apple.com/research/apple-foundation-models-2025-updates
[apple-req]: https://support.apple.com/en-us/121115
[ctx]: https://developer.apple.com/forums/thread/806542
[llamacpp]: https://github.com/ggml-org/llama.cpp
[mlx]: https://github.com/ml-explore/mlx-swift-lm
[qwen35]: https://huggingface.co/collections/unsloth/qwen35
[qwen3-4b]: https://huggingface.co/Qwen/Qwen3-4B
[gemma4]: https://ai.google.dev/gemma/docs/core
[gemma4-blog]: https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/
[bench]: https://github.com/ggml-org/llama.cpp/discussions/4167
