enum Sentiment {
  Positive
  Negative
  Neutral
}

class Resume {
  name string
  skills string[]
  years_experience int
}

class NamedGreeting {
  greeting string
  name string
}

function SayHello(name: string) -> string {
  client OpenRouterClient
  prompt #"
    Say "Hello, {{ name }}!" and nothing else.
  "#
}

function ClassifySentiment(text: string) -> Sentiment {
  client OpenRouterClient
  prompt #"
    Classify the sentiment of the following text as Positive, Negative, or Neutral.

    Text: {{ text }}

    {{ ctx.output_format }}
  "#
}

function ExtractGreeting(text: string) -> NamedGreeting {
  client OpenRouterClient
  prompt #"
    Extract the greeting and name from this text.

    Text: {{ text }}

    {{ ctx.output_format }}
  "#
}

function ExtractResume(text: string) -> Resume {
  client OpenRouterClient
  prompt #"
    Extract structured resume information from this text.

    Text: {{ text }}

    {{ ctx.output_format }}
  "#
}
