import SwiftUI

struct ResultsCard: View {
    let result: TextAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Results")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(result.title)
                .font(.title2)
                .fontWeight(.bold)

            Text(result.summary)
                .font(.body)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(result.themes, id: \.self) { theme in
                        ThemeChip(label: theme)
                    }
                }
            }

            SentimentBadge(sentiment: result.sentiment)

            VStack(alignment: .leading, spacing: 8) {
                Text("Key Points")
                    .font(.headline)
                ForEach(result.key_points, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(point)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}
