retry_policy Retry {
  max_retries 3
  strategy {
    type exponential_backoff
  }
}

client<llm> OpenRouterClient {
  provider openrouter
  retry_policy Retry
  options {
    model "stepfun/step-3.5-flash:free"
    api_key env.OPENROUTER_API_KEY
    temperature 0
    max_tokens 8192
  }
}
