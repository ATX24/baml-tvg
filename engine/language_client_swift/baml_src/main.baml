// Simple BAML project for Swift SDK testing
// Uses OpenRouter (OpenAI-compatible) so no OpenAI account needed

generator SwiftClient {
  output_type swift
  output_dir "../Sources/BamlClient"
  version "0.219.0"
}

client<llm> OpenRouter {
  provider openai
  options {
    model "meta-llama/llama-3.2-3b-instruct:free"
    base_url "https://openrouter.ai/api/v1"
    api_key env.OPENROUTER_API_KEY
  }
}

function SayHello(name: string) -> string {
  client OpenRouter
  prompt #"
    Say hello to {{ name }} in a friendly one-sentence greeting.
    Return only the greeting, no extra text.
  "#
}

function Classify(text: string) -> string {
  client OpenRouter
  prompt #"
    Classify the following text as one of: positive, negative, or neutral.
    Reply with only the single word label.

    Text: {{ text }}
  "#
}
