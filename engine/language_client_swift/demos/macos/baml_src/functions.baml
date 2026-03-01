enum Sentiment {
  Positive
  Negative
  Neutral
  Mixed
}

class TextAnalysis {
  title      string    @description("short title, max 10 words")
  summary    string    @description("2-3 sentence summary")
  themes     string[]  @description("3-5 topic tags")
  sentiment  Sentiment
  key_points string[]  @description("3-5 short bullet takeaways")
}

function AnalyzeText(text: string) -> TextAnalysis {
  client OpenRouterClient
  prompt #"
    Analyze the following text and extract key information.

    Text: {{ text }}

    {{ ctx.output_format }}
  "#
}
