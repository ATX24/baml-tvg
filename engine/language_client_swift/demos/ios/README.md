# Scribe — iOS Demo

SwiftUI app that uses BAML + OpenRouter to analyze pasted text and returns structured output: title, summary, themes, sentiment, and key points.

## How it works

```
BamlCFFI.xcframework  ← static Rust lib linked directly in the Xcode project
       ↓
   BamlSwift          ← via local package reference to engine/language_client_swift
       ↓
   baml_client/       ← generated BAML client compiled as app sources
       ↓
    Scribe            ← SwiftUI app
```

No symlinks or setup scripts. Just open the project.

## Setup

### 1. Build the XCFramework (if not done yet)

```bash
cd engine/language_client_swift
./scripts/build-xcframework.sh --release
```

This produces `engine/language_client_swift/BamlCFFI.xcframework`, which the Xcode project references at `../../../BamlCFFI.xcframework`.

### 2. Open in Xcode

```bash
open Scribe.xcodeproj
```

Xcode will resolve `BamlSwift` from the local `engine/language_client_swift` package automatically.

### 3. Add your API key

**Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables**

Add: `OPENROUTER_API_KEY` = `sk-or-...`

### 4. Run

Select **iPhone 16** (or any iOS 16+ simulator) and press **⌘R**.

## File layout

```
ios/
├── Scribe.xcodeproj/          # open this in Xcode
├── Scribe/
│   ├── ScribeApp.swift        # @main App entry point
│   ├── ContentView.swift      # root view
│   ├── AnalysisViewModel.swift # ObservableObject, calls AnalyzeText
│   ├── Views/
│   │   ├── InputCard.swift    # TextEditor + Analyze button
│   │   ├── ResultsCard.swift  # full result layout
│   │   ├── ThemeChip.swift    # pill tag for each theme
│   │   └── SentimentBadge.swift # colored badge
│   └── baml_client/           # generated BAML client (same as macOS demo)
│       ├── BamlClient.swift
│       ├── BamlFunctions.swift
│       ├── BamlFunctionsStream.swift
│       ├── BamlTypes.swift    # TextAnalysis struct
│       └── BamlEnums.swift    # Sentiment enum
└── baml_src/                  # BAML source files (for reference)
    ├── clients.baml
    └── functions.baml
```

## BAML schema

```
enum Sentiment { Positive  Negative  Neutral  Mixed }

class TextAnalysis {
  title      string
  summary    string
  themes     string[]
  sentiment  Sentiment
  key_points string[]
}

function AnalyzeText(text: string) -> TextAnalysis {
  client OpenRouterClient  // reads env.OPENROUTER_API_KEY at call time
  prompt #"
    Analyze the following text and extract key information.
    Text: {{ text }}
    {{ ctx.output_format }}
  "#
}
```
