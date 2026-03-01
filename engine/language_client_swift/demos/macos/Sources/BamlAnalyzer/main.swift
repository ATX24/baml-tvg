import Foundation
import BamlClient

// MARK: - Sample text (used when --stdin is not passed)

private let sampleText = """
The global shift toward renewable energy is accelerating at an unprecedented pace. \
Solar panel installations doubled worldwide over the past three years, driven by \
rapidly falling costs and supportive government policies. Wind power capacity has \
also seen remarkable growth, particularly offshore. However, experts note that \
grid storage remains the primary bottleneck — without better battery technology \
and smarter grid infrastructure, intermittent generation cannot reliably replace \
fossil fuel baseloads. Private investment in clean energy reached record highs \
last year, signaling strong market confidence in the sector's future.
"""

// MARK: - Read input

let inputText: String
if CommandLine.arguments.contains("--stdin") {
    var lines: [String] = []
    while let line = readLine() {
        lines.append(line)
    }
    inputText = lines.joined(separator: "\n")
} else {
    inputText = sampleText
}

// MARK: - Run analysis

print("Analyzing...\n")

var analysisResult: TextAnalysis?
var analysisError: Error?
let sem = DispatchSemaphore(value: 0)

Task {
    do {
        analysisResult = try await AnalyzeText(text: inputText)
    } catch {
        analysisError = error
    }
    sem.signal()
}

sem.wait()

// MARK: - Print result

if let error = analysisError {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}

if let result = analysisResult {
    let emoji: String
    switch result.sentiment {
    case .Positive: emoji = "😊"
    case .Negative: emoji = "😟"
    case .Neutral:  emoji = "😐"
    case .Mixed:    emoji = "🤔"
    }

    print("  Title      : \(result.title)")
    print("  Summary    : \(result.summary)")
    print("  Themes     : \(result.themes.joined(separator: ", "))")
    print("  Sentiment  : \(emoji) \(result.sentiment.rawValue)")
    print("  Key Points :")
    result.key_points.forEach { print("    • \($0)") }
}
