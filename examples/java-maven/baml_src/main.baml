client<llm> Gemini {
  provider google-ai
  options {
    model "gemini-2.0-flash"
    api_key env.GOOGLE_API_KEY
  }
}

function Summarize(text: string) -> string {
  client Gemini
  prompt #"
    Summarize the following text in one sentence:
    {{ text }}
  "#
}
