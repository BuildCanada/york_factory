require "ruby_llm"

RubyLLM.configure do |config|
  config.anthropic_api_key = Rails.application.credentials.dig(:llm, :anthropic_api_key) || ENV["ANTHROPIC_API_KEY"]
  config.openai_api_key    = Rails.application.credentials.dig(:llm, :openai_api_key)    || ENV["OPENAI_API_KEY"]
  config.gemini_api_key    = Rails.application.credentials.dig(:llm, :gemini_api_key)    || ENV["GEMINI_API_KEY"]
end
