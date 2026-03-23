class LlmClient
  MODEL = "claude-haiku-4-5-20251001"
  MAX_CALLS_PER_RUN = 1000

  class << self
    def instance
      @instance ||= new
    end
  end

  def initialize
    @client = Anthropic::Client.new
    @call_count = 0
  end

  def entity_resolve(org_name:, candidates:)
    raise "LLM call limit exceeded (#{MAX_CALLS_PER_RUN})" if @call_count >= MAX_CALLS_PER_RUN

    @call_count += 1

    candidate_list = candidates.map.with_index { |c, i| "#{i + 1}. #{c}" }.join("\n")

    prompt = <<~PROMPT
      You are matching a government organization name from a budget document to a list of canonical organization names.

      Organization name to match: "#{org_name}"

      Candidate canonical names:
      #{candidate_list}

      Respond with JSON only:
      {
        "match": "exact canonical name from the list above, or null if no match",
        "confidence": 0.0 to 1.0,
        "reasoning": "brief explanation"
      }

      If none of the candidates are a reasonable match, set match to null and confidence to 0.
    PROMPT

    response = @client.messages.create(
      model: MODEL,
      max_tokens: 256,
      messages: [{ role: "user", content: prompt }]
    )

    text = response.content.first.text
    parsed = JSON.parse(text)

    {
      match: parsed["match"],
      confidence: parsed["confidence"].to_f,
      reasoning: parsed["reasoning"],
      raw_prompt: prompt,
      raw_response: text
    }
  rescue JSON::ParserError => e
    { match: nil, confidence: 0.0, reasoning: "Failed to parse LLM response: #{e.message}", raw_prompt: prompt, raw_response: text }
  rescue Anthropic::Error => e
    { match: nil, confidence: 0.0, reasoning: "LLM API error: #{e.message}", raw_prompt: prompt, raw_response: nil }
  end

  def generate_sql(question:, schema_description:)
    prompt = <<~PROMPT
      You are a SQL query generator for a Canadian federal fiscal data database.
      Generate a PostgreSQL query that answers the user's question.

      IMPORTANT RULES:
      - Only generate SELECT queries. Never INSERT, UPDATE, DELETE, DROP, ALTER, or TRUNCATE.
      - Always include source information (fiscal_year, organization name, document_type) for citation.
      - Limit results to 100 rows unless the user asks for more.
      - Use proper JOINs to include organization names in results.

      DATABASE SCHEMA:
      #{schema_description}

      USER QUESTION: #{question}

      Respond with JSON only:
      {
        "sql": "the SELECT query",
        "explanation": "brief explanation of what this query does"
      }
    PROMPT

    response = @client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 1024,
      messages: [{ role: "user", content: prompt }]
    )

    text = response.content.first.text
    parsed = JSON.parse(text)

    { sql: parsed["sql"], explanation: parsed["explanation"] }
  rescue JSON::ParserError, Anthropic::Error => e
    { sql: nil, explanation: "Error: #{e.message}" }
  end

  def reset_call_count!
    @call_count = 0
  end
end
