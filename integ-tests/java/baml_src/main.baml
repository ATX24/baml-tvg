client<llm> GPT35 {
  provider openai
  options {
    model "gpt-4o-mini"
    api_key env.OPENAI_API_KEY
  }
}

function LLMEcho(input: string) -> string {
  client GPT35
  prompt #"Echo exactly the input: {{input}}"#
}

class Person {
  name string
  age int
}

enum Mood {
  HAPPY
  SAD
}

type IntOrString = int | string

function DescribePerson(p: Person) -> string {
  client GPT35
  prompt #"
You are a friendly assistant. Describe the person briefly using their name and age.
Name: {{p.name}}
Age: {{p.age}}
"#
}

function ClassifyMood(text: string) -> string {
  client GPT35
  prompt #"
Read the following text and respond with exactly one word: HAPPY or SAD.
Text: {{text}}
"#
}

function UseIntOrString(u: IntOrString) -> string {
  client GPT35
  prompt #"
You will receive either an integer or a string. Return a short message saying which you received and its value.
Value: {{u}}
"#
}

