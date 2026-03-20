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
    Write a 500 word analysis of the following text:
    {{ text }}
  "#
}
