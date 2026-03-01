import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AnalysisViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    InputCard(viewModel: viewModel)

                    if let result = viewModel.result {
                        ResultsCard(result: result)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Scribe")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
