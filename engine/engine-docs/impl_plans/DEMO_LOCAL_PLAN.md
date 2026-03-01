# BAML Swift — Local Model Demo Plan

A third demo showing BAML running **100% on-device** on an iOS device using a quantized small model via ExecuTorch. No network calls, no API key required.

---

## Concept

The existing iOS demo (Scribe) sends text to OpenRouter for inference. This demo replaces that with a locally running model — the BAML structured output layer stays identical; only the inference backend changes.

**Selling point**: BAML's prompt formatting and response parsing work independently of where inference happens. Swap the client, keep everything else.

---

## Model

**Qwen3-0.6B** (Unsloth quantized, INT4 weights / INT8 dynamic activations)

- Export format: `.pte` (PyTorch ExecuTorch)
- Size: ~472 MB on disk
- Performance: ~40 tokens/s on iPhone 15 Pro
- Fits in memory on any modern iPhone (A15+)

Other viable candidates: Gemma3-1B, Llama3.2-1B, Phi-4-mini (all supported by Unsloth's phone-deployment export path).

---

## Architecture

### The problem

BAML's current client infrastructure is HTTP-based: the engine formats a prompt, makes an HTTP request to a provider (OpenRouter, OpenAI, etc.), and parses the response. ExecuTorch runs inference in-process — there is no HTTP endpoint.

### Two viable approaches

#### Option A — Local HTTP bridge (lower engineering effort)

Run a minimal HTTP server inside the app on `localhost` that wraps ExecuTorch. Point BAML's client at `http://localhost:PORT` using an `openai-generic` provider.

```
BAML engine
  → formats prompt (existing)
  → POST http://localhost:11434/v1/chat/completions   ← thin NWListener server in-app
       → ExecuTorch inference
       → streams tokens back as SSE
  → parses structured response (existing)
```

Pros:
- Zero changes to BAML engine or generated client
- Reuses existing OpenAI-compatible client path
- Could also point at a Mac running Ollama over LAN (useful for dev)

Cons:
- Running an HTTP server inside an iOS app is unusual and adds complexity
- Adds latency (loopback, serialization)
- Background server lifecycle management on iOS is tricky

#### Option B — Custom Swift inference provider (higher value, more work)

Add a new BAML client provider type (`local-executorch` or similar) that routes inference to a user-supplied Swift closure instead of making an HTTP call. The BAML engine formats the prompt and hands it to a registered handler; the handler runs ExecuTorch and returns the raw text; BAML parses the structured output.

```baml
client LocalModel {
  provider local-executorch
  options {
    model "qwen3-0.6b.pte"
  }
}
```

```swift
// App registers the handler at startup
BamlRuntime.registerLocalProvider { prompt in
    return try await executorchModel.generate(prompt)
}
```

Pros:
- Clean architecture, no loopback overhead
- Demonstrates BAML's extensibility as a feature
- Production-viable pattern (useful beyond this demo)

Cons:
- Requires engine work: new provider type in `baml-runtime`
- More plumbing in the generated Swift client

### Recommendation for demo

**Start with Option A** (local HTTP bridge) to get something working fast and validate the UX. The demo value is showing BAML + on-device inference together — the bridge implementation detail doesn't matter for the demo video. Option B is the right long-term architecture and can follow.

---

## Model Preparation

Using Unsloth's phone-deployment export:

```python
# Run in Google Colab (Unsloth notebook)
from unsloth import FastLanguageModel

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/Qwen3-0.6B",
    quantization_type="phone-deployment",  # INT4 weights + INT8 dynamic activations
)

# Export to .pte
model.save_pretrained_executorch("qwen3-0.6b-phone", tokenizer=tokenizer)
```

Outputs:
- `qwen3-0.6b-phone.pte` (~472 MB) — the model
- `tokenizer.json` — the tokenizer

Transfer to device via Xcode file sharing (Finder → device → Files tab).

---

## iOS Integration

Use Meta's **ExecuTorch iOS framework** from the `executorch-examples` repo (`apple/etLLM`).

### Xcode setup

1. Clone `executorch-examples`, copy the ExecuTorch XCFramework into the project
2. Add `ExecuTorch.xcframework` under *Frameworks, Libraries, and Embedded Content*
3. Add `BamlCFFI.xcframework` (same as existing iOS demo)
4. Add local `engine/language_client_swift` package

### Model loading (Option A sketch)

```swift
import ExecuTorch

class LocalInferenceServer {
    private var runner: LLMRunner?

    func load(modelURL: URL, tokenizerURL: URL) throws {
        runner = try LLMRunner(modelPath: modelURL.path,
                               tokenizerPath: tokenizerURL.path)
    }

    // Start a loopback HTTP server on a random port
    // Accepts POST /v1/chat/completions, streams SSE tokens from runner
    func startServer() -> Int { /* returns port */ }
}
```

### BAML client config

```baml
client LocalModel {
  provider openai-generic
  options {
    base_url "http://localhost:{{ env.LOCAL_MODEL_PORT }}/v1"
    model "qwen3-0.6b"
    api_key "none"
  }
}

function AnalyzeText(text: string) -> TextAnalysis {
  client LocalModel          // ← only line that changes vs cloud demo
  prompt #"
    Analyze this text.
    {{ text }}
    {{ ctx.output_format }}
  "#
}
```

---

## Demo App — "Scribe Local"

Same UI as the existing Scribe iOS demo with two changes:

1. **No API key required** — remove the settings/key entry screen
2. **Status indicator** — show "On-device · Qwen3 0.6B" instead of "OpenRouter"

```
┌─────────────────────────────┐
│  Scribe              🔒 Local│  ← badge shows on-device mode
├─────────────────────────────┤
│                             │
│  ┌───────────────────────┐  │
│  │ Paste or type text    │  │
│  └───────────────────────┘  │
│                             │
│        [ Analyze ]          │
│                             │
├─────────────────────────────┤
│  Results                    │
│  ...                        │
│                             │
│  ⚡ 38 tok/s · on-device    │  ← token/s counter
└─────────────────────────────┘
```

### Location

```
demos/ios-local/
├── README.md
├── ScribeLocal.xcodeproj/
├── ScribeLocal/
│   ├── ScribeLocalApp.swift
│   ├── ContentView.swift          # same as Scribe, adds local badge
│   ├── AnalysisViewModel.swift    # same interface, different client
│   ├── LocalInferenceServer.swift # Option A: loopback HTTP server
│   ├── ModelLoader.swift          # loads .pte + tokenizer from app sandbox
│   └── baml_client/               # identical to existing iOS demo
│       └── ...
└── baml_src/
    ├── clients.baml               # LocalModel client pointing to localhost
    └── functions.baml             # AnalyzeText — identical schema
```

---

## Build Order

1. Export model via Unsloth Colab → download `qwen3-0.6b-phone.pte` + `tokenizer.json`
2. Build `BamlCFFI.xcframework` (existing script)
3. Open `demos/ios-local/ScribeLocal.xcodeproj` in Xcode
4. Transfer model files to device via Finder file sharing
5. Run on physical device (requires paid Apple Developer account for `increased-memory-limit` entitlement)

---

## Key Differences from Cloud Demo

| | Scribe (cloud) | Scribe Local |
|---|---|---|
| Inference | OpenRouter API | ExecuTorch on-device |
| API key | Required | None |
| Privacy | Data leaves device | 100% on-device |
| Latency | Network + inference | Inference only (~40 tok/s) |
| Model | Any cloud model | Qwen3-0.6B (472 MB) |
| BAML schema | Identical | Identical |
| Generated client | Identical | Identical |
| Client config | `provider openai` | `provider openai-generic` → localhost |

The BAML schema and generated Swift client are **identical** — only the `clients.baml` file changes.

---

## Open Questions

- **ExecuTorch Swift API stability**: the `etLLM` project is a demo app, not a stable SDK. Need to verify the Swift inference API surface before committing to Option A vs B.
- **Memory limit entitlement**: physical device deployment requires a paid Apple Developer account. Simulator works without it but won't reflect real performance.
- **Model fit**: Qwen3-0.6B at 472 MB fits comfortably; larger models (1B+) may need the `increased-memory-limit` entitlement or will OOM on older devices.
- **Structured output reliability**: smaller models are less reliable at following BAML's output format instructions. May need a simpler schema (fewer fields, no enums) compared to the cloud demo.
