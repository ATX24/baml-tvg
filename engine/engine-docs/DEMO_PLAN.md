# BAML Swift — Demo Plan

Two demos showing BAML in real Swift apps: a macOS CLI runner and an iOS mini-app.

---

## Demo 1 — macOS (SPM executable)

**Location**: `demos/macos/`

Simple SPM executable that runs BAML in a terminal. Good for verifying the dylib path works and showing the raw API without any UI noise.

### What it does
Reads text from stdin (or a hardcoded sample), calls `AnalyzeText`, and pretty-prints the result.

```
$ OPENROUTER_API_KEY=sk-or-... \
  BAML_LIBRARY_PATH=engine/target/aarch64-apple-darwin/release/libbaml_cffi.dylib \
  swift run

Analyzing...

  Title      : The Future of Renewable Energy
  Summary    : Solar and wind adoption is accelerating globally...
  Themes     : clean energy, policy, investment, climate
  Sentiment  : Positive
  Key Points :
    • Global solar capacity doubled in 3 years
    • Policy incentives driving private investment
    • Grid storage remains the main bottleneck
```

### Structure
```
demos/macos/
├── Package.swift              # executableTarget, depends on language_client_swift (local path)
├── baml_src/
│   ├── clients.baml           # OpenRouter, stepfun/step-3.5-flash:free
│   └── functions.baml         # AnalyzeText(text) -> TextAnalysis
├── baml_client/               # hand-written generated client
│   ├── BamlClient.swift
│   ├── BamlFunctions.swift
│   ├── BamlFunctionsStream.swift
│   ├── BamlTypes.swift        # TextAnalysis struct
│   └── BamlEnums.swift        # Sentiment enum
└── Sources/BamlAnalyzer/
    └── main.swift             # reads stdin → calls AnalyzeText → prints result
```

### BAML schema
```
class TextAnalysis {
  title      string    @description("short title, max 10 words")
  summary    string    @description("2-3 sentence summary")
  themes     string[]  @description("3-5 topic tags")
  sentiment  Sentiment
  key_points string[]  @description("3-5 short bullet takeaways")
}

enum Sentiment { Positive  Negative  Neutral  Mixed }

function AnalyzeText(text: string) -> TextAnalysis {
  client OpenRouterClient
  prompt #" Analyze this text. {{ text }}  {{ ctx.output_format }} "#
}
```

---

## Demo 2 — iOS Mini App (Xcode / SwiftUI)

**Location**: `demos/ios/`

A proper SwiftUI iOS app. User pastes any text, taps **Analyze**, and the app calls BAML via the static XCFramework and renders a structured result card.

### App name
**Scribe** — *Understand any text instantly*

### UI flow

```
┌─────────────────────────────┐
│  Scribe                  ⚙️ │
├─────────────────────────────┤
│                             │
│  ┌───────────────────────┐  │
│  │ Paste or type text    │  │  ← TextEditor, min height 160pt
│  │ here...               │  │
│  └───────────────────────┘  │
│                             │
│        [ Analyze ]          │  ← Button, disabled while loading
│                             │
├─────────────────────────────┤
│  Results                    │
│                             │
│  The Future of Renewables   │  ← title (headline)
│                             │
│  Solar and wind adoption... │  ← summary (body)
│                             │
│  🏷 clean energy  🏷 policy │  ← themes as chip row
│  🏷 investment               │
│                             │
│  😊 Positive                │  ← sentiment badge (colored)
│                             │
│  Key Points                 │
│  • Global solar capacity... │  ← bulleted list
│  • Policy incentives...     │
│  • Grid storage remains...  │
│                             │
└─────────────────────────────┘
```

### Structure
```
demos/ios/
├── README.md
├── Scribe.xcodeproj/          # Minimal Xcode project
├── Scribe/
│   ├── ScribeApp.swift        # @main entry point
│   ├── ContentView.swift      # root view (input + results)
│   ├── AnalysisViewModel.swift # @Observable, calls AnalyzeText async
│   ├── Views/
│   │   ├── InputCard.swift    # TextEditor + button
│   │   ├── ResultsCard.swift  # full result layout
│   │   ├── ThemeChip.swift    # single tag chip
│   │   └── SentimentBadge.swift # colored badge
│   └── baml_client/          # same generated client as macOS demo
│       ├── BamlClient.swift
│       ├── BamlFunctions.swift
│       ├── BamlFunctionsStream.swift
│       ├── BamlTypes.swift
│       └── BamlEnums.swift
└── baml_src/
    ├── clients.baml
    └── functions.baml
```

### BAML schema
Same schema as the macOS demo (`TextAnalysis` + `Sentiment` + `AnalyzeText`). The `baml_client/` folder is identical between the two demos.

### Xcode project setup
- **Deployment target**: iOS 16+
- **Framework**: Add `BamlCFFI.xcframework` under *Frameworks, Libraries, and Embedded Content* → **Embed & Sign**
- **Secret**: add `OPENROUTER_API_KEY` to the scheme's Run environment variables (never hardcode)
- **Dependency**: add the local `engine/language_client_swift` package via *Add Package → Add Local…*

### ViewModel sketch
```swift
@MainActor
@Observable
class AnalysisViewModel {
    var inputText   = ""
    var result: TextAnalysis?
    var isLoading   = false
    var errorMessage: String?

    func analyze() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        result    = nil
        errorMessage = nil
        do {
            result = try await AnalyzeText(text: inputText)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
```

---

## Shared BAML Client

Both demos use the same `baml_client/` files. The only difference is how BamlSwift is
linked:

| Demo | Linking | Setup |
|------|---------|-------|
| macOS | `dlopen` at runtime | `BAML_LIBRARY_PATH` env var |
| iOS | Static (XCFramework) | `BamlCFFI.xcframework` in Xcode project |

The `BamlRuntime` class handles both paths internally — no app code changes required.

---

## Build Order

1. Build `libbaml_cffi.dylib` (macOS) or `BamlCFFI.xcframework` (iOS)
2. Build macOS demo: `swift run` from `demos/macos/`
3. Build iOS demo: open `demos/ios/Scribe.xcodeproj` in Xcode, select iOS Simulator, run
