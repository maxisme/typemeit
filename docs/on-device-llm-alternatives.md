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

With the mishearing rule added in September 2026 the model does turn "Alexa set
time up for half an hour" into "Alexa set a timer for half an hour". It still
drops words in some short transcripts and ignores every instruction about layout;
see the measurements below.

## What changes in macOS 27

Announced at WWDC in June 2026, shipping autumn 2026. [What's new in the
Foundation Models framework][wwdc26-241], [Michael Tsai's round-up][mjtsai]

- The on-device model is rebuilt: better instruction following, image input, and
  an 8,192-token context reported by the new `model.contextSize` property, with
  `tokenCount(for:)` to measure prompts. The 4,096 limit above applies to macOS 26.
- A `LanguageModel` protocol lets any model back a `LanguageModelSession`. Apple
  ships two open-source implementations: `CoreAILanguageModel` runs local models
  on the Neural Engine and `MLXLanguageModel` runs them on the GPU. This is the
  route for the Qwen and Gemma models below on macOS 27, without embedding
  llama.cpp, and the existing `@Generable` guided generation and greedy sampling
  carry over unchanged.
- Private Cloud Compute gets a 32,000-token context and a reasoning level, free
  for apps under two million lifetime downloads. Not on-device, so out of scope
  for this note.

Everything measured below is the macOS 26 model. Rerun `Scripts/llm-bench` on
macOS 27 before deciding anything; the recommendation at the end assumes the
macOS 26 numbers.

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

## Measured, September 2026

`Scripts/llm-bench/run.sh` runs the nine cases in `Scripts/cleanup-eval/cases.json`
and three long dictations of 58 to 91 words through each engine in-process: Apple
Intelligence through Foundation Models exactly as the app does, and each GGUF
through libllama with Metal, greedy sampling and a JSON grammar pinning the output
to one field, which is the closest equivalent of guided generation. Machine: M4
(base), 24 GB, macOS 26.6.1, llama.cpp 0.4.0, Q4_K_M weights. The prompt is read
from `PostProcessor.swift`, so these are the app's live instructions.

| Engine | File | Load | Resident with weights | Short cases | Long layouts | Mean short case | Mean long dictation | Generation tok/s |
|---|---|---|---|---|---|---|---|---|
| Apple Intelligence | none | 0 | none in our process | 6/9 | 0/3 | 0.6 s | 1.7 s | ~18 (estimated) |
| Qwen3.5 2B | 1.3 GB | 0.9 s | 1.7 GB | 8/9 | 0/3 | 1.5 s | 5.3 s | 24 |
| Qwen3.5 4B | 2.7 GB | 1.9 s | 3.2 GB | 8/9 | 1/3 | 3.0 s | 9.8 s | 15 |
| Gemma 4 E2B | 3.1 GB | 2.4 s | 3.3 GB | 8/9 | 0/3 | 1.7 s | 6.6 s | 21 |
| Gemma 4 E4B | 5.0 GB | 3.5 s | 5.3 GB | 8/9 | 1/3 | 2.8 s | 10.5 s | 15 |

A case passes when the output matches any of its accepted wordings with case and
punctuation ignored, so "cafe" for "café" and "and third" for "third" both count.
The long layouts are compared line by line with blank lines dropped, so the list
has to come out as numbered lines but paragraph spacing is free.

Machine-wide CPU sat at 22 to 25 percent busy for every engine, Apple included,
so CPU is not what separates them; the GGUF engines spend 14 to 17 CPU-seconds
per run in our process on sampling and the grammar while the GPU generates.
Foundation Models does not report token counts, so its tok/s is estimated at 1.3
tokens a word. Load time for the GGUFs is from a warm disk cache; the first load
after a reboot reads the whole file.

What the failures are:

- Apple Intelligence drops words: "that will be twenty five dollars please" comes
  back as "twenty-five dollars please" and "um so I think we should uh ship it on
  Friday" as "we should ship it on Friday". It leaves one "um" in the list case.
  None of the other engines drop words in the short cases.
- Each GGUF misses one short case: Qwen3.5 2B and Gemma 4 E2B a currency
  conversion ("twenty-five dollars" kept, or "That will be" dropped), Qwen3.5 4B
  rewrites "half an hour" as "30 minutes", Gemma 4 E4B drops "So".
- Gemma 4 E2B is a 3 GB file despite the 2B name because the per-layer
  embeddings are stored in full; the memory table above that put it at 1.3 GB is
  wrong for the GGUF builds.

Formatting. The long dictations ran with an added rule asking for a lead-in
ending in a colon, counted items as a numbered list, and a blank line between
topics. The target for the first one is:

```
Okay so three things for tomorrow:
1. We need to finish the landing page
2. Call the accountant about the VAT return.
3. Book the train tickets for Friday.

Also separately, I was thinking about the pricing page. ...
```

Qwen3.5 4B and Gemma 4 E4B produce exactly that shape, and 4B also lays out the
supplier notes as a numbered list with a separate paragraph for the change of
contact. Both miss the third case only on wording. Apple Intelligence, Qwen3.5
2B and Gemma 4 E2B return one block; E2B writes "1. 2. 3." inline in the sentence.
On the 91-word dictation Apple Intelligence and Qwen3.5 2B return the transcript
untouched, lower case and all, which looks like the output field being filled
with the input when the model gives up. The 4B-class models pay for the layout
with 7 to 11 seconds a dictation against Apple's 1.7.

## Recommendation

Keep Apple Intelligence as the default. It is four to six times faster than
anything we could embed and costs no memory in our process, and its failures are
dropped words in short transcripts that a prompt change may still fix.

The measurements change one thing in the earlier advice: the model to try first
is Qwen3.5 4B, with Gemma 4 E4B as the alternative. Those two are the only ones
that lay out a long dictation, and 4B is the smaller file by 2.3 GB. The cost is
3.3 GB resident while loaded and about ten seconds for a paragraph, so it belongs
behind a setting, loaded on demand and unloaded on the `Fixed.modelUnloadIdle`
timer, and used only above a length threshold where layout matters. On macOS 27
run it through `MLXLanguageModel` rather than embedding llama.cpp; on macOS 26
llama.cpp is the option. Before either, rerun the benchmark on macOS 27's
rebuilt system model, which may make the whole question moot.

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
[wwdc26-241]: https://developer.apple.com/videos/play/wwdc2026/241/
[mjtsai]: https://mjtsai.com/blog/2026/06/16/apple-foundation-models-in-appleos-27/
