import SwiftUI

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var result: TextAnalysis?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func analyze() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        result = nil
        errorMessage = nil
        do {
            result = try await AnalyzeText(text: inputText)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
