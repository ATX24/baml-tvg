import SwiftUI

struct InputCard: View {
    @ObservedObject var viewModel: AnalysisViewModel

    private var inputIsEmpty: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text to analyze")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.inputText)
                .frame(minHeight: 160)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

            Button {
                Task { await viewModel.analyze() }
            } label: {
                Group {
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Analyze").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(inputIsEmpty || viewModel.isLoading
                    ? Color.accentColor.opacity(0.5)
                    : Color.accentColor)
                .foregroundStyle(.white)
                .cornerRadius(10)
            }
            .disabled(inputIsEmpty || viewModel.isLoading)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}
