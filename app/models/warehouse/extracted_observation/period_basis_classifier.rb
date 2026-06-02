class Warehouse::ExtractedObservation::PeriodBasisClassifier < ActiveRecord::AssociatedObject
  LLM_MODEL = "claude-haiku-4-5-20251001"
  BATCH_SIZE = 10
  VALID_LABELS = Warehouse::ExtractedObservation::PERIOD_BASES
  AUTO_ACCEPT_CONFIDENCE = 0.8

  Result = Struct.new(:period_basis, :confidence, :reasoning, :raw_response, keyword_init: true)

  # Single-row classification. Returns a Result.
  def classify
    payload = [ build_row(extracted_observation) ]
    parsed = call_llm(payload).first
    interpret(parsed)
  end

  # Class-level batch driver. Yields { id, result } pairs so callers can stream updates.
  def self.classify_batch(observations)
    return if observations.empty?

    observations.each_slice(BATCH_SIZE) do |slice|
      classifier = new(slice.first)  # singleton-ish; the row arg isn't used in batch path
      payload = slice.map { |c| classifier.send(:build_row, c) }
      parsed_rows = classifier.send(:call_llm, payload)
      by_id = parsed_rows.index_by { |r| r["id"] }

      slice.each do |observation|
        result = classifier.send(:interpret, by_id[observation.id])
        yield observation, result if block_given?
      end
    end
  end

  private

  def build_row(observation)
    measure = observation.measure
    {
      id: observation.id,
      measurement_year: observation.measurement_year,
      value_type: observation.value_type,
      measure_name: measure&.canonical_name,
      notes: observation.notes.to_s.strip
    }
  end

  def call_llm(rows)
    prompt = build_prompt(rows)
    raw = RubyLLM.chat(model: LLM_MODEL).ask(prompt).content.strip
    json = extract_json_array(raw)
    JSON.parse(json)
  rescue JSON::ParserError, RuntimeError => e
    Rails.logger.warn("PeriodBasisClassifier: parse error #{e.class}: #{e.message}; raw=#{raw&.slice(0, 200)}")
    rows.map { |r| { "id" => r[:id], "period_basis" => nil, "confidence" => 0.0, "reasoning" => "parse_failed" } }
  end

  def build_prompt(rows)
    header = <<~PROMPT
      You are classifying each row's reporting period from the `notes` field of a
      Toronto budget KPI citation. Output one of exactly these five labels:

        full_year   — annual total or average, full 12-month period.
        ytd_q1      — year-to-date through Q1 (Jan–Mar, ~3 months).
        ytd_q2      — year-to-date through Q2 (Jan–Jun, ~6 months).
        ytd_q3      — year-to-date through Q3 (Jan–Sep, ~9 months).
        as_of_date  — point-in-time snapshot (e.g., "as of June 30", "as at Dec 31").

      Rules:
      - "cumulative" alone usually means full_year unless paired with a quarter.
      - "as at" / "as of" → as_of_date.
      - "Q1 YTD" → ytd_q1; "year-to-date through Q2" → ytd_q2; etc.
      - "partial" without a quarter modifier → ytd_q2 if no quarter is mentioned but a partial-year value is implied; otherwise full_year.
      - If the notes are silent or ambiguous, return full_year with confidence 0.5.
      - Use measure_name only to disambiguate (e.g., a stock value like "beds occupied" with "as at" is as_of_date).

      Respond ONLY with a JSON array, one element per input row, in the same order.
      Each element: { "id": <int>, "period_basis": "<label>", "confidence": 0.0..1.0, "reasoning": "<short>" }

      INPUT ROWS:
    PROMPT

    rows_block = rows.map do |r|
      "- id=#{r[:id]} year=#{r[:measurement_year]} value_type=#{r[:value_type]} " \
        "measure=#{r[:measure_name].inspect} notes=#{r[:notes].inspect}"
    end.join("\n")

    header + rows_block
  end

  def extract_json_array(raw)
    # Strip Markdown fences if Claude wraps the response.
    cleaned = raw.gsub(/\A```(?:json)?\s*/i, "").gsub(/```\s*\z/, "").strip
    return cleaned if cleaned.start_with?("[")

    start_idx = cleaned.index("[")
    end_idx = cleaned.rindex("]")
    raise "no JSON array in response" unless start_idx && end_idx && end_idx > start_idx

    cleaned[start_idx..end_idx]
  end

  def interpret(parsed_row)
    return Result.new(period_basis: "full_year", confidence: 0.0, reasoning: "missing_response") if parsed_row.nil?

    label = parsed_row["period_basis"]
    label = nil unless VALID_LABELS.include?(label)
    Result.new(
      period_basis: label,
      confidence: parsed_row["confidence"].to_f,
      reasoning: parsed_row["reasoning"].to_s,
      raw_response: parsed_row
    )
  end
end
