import SwiftUI

/// Colored pill showing sentiment + emoji.
struct SentimentBadge: View {
    let sentiment: Sentiment

    private var color: Color {
        switch sentiment {
        case .Positive: .green
        case .Negative: .red
        case .Neutral:  .gray
        case .Mixed:    .orange
        }
    }

    var body: some View {
        Text(sentiment.rawValue)
            .fontWeight(.semibold)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(20)
    }
}
