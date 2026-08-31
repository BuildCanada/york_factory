class Warehouse::FinancialStatementExtraction::VisualEvidenceReviewer
  DEFAULT_MODEL = ENV.fetch("MUNICIPAL_FINANCIAL_VISUAL_REVIEW_MODEL", "claude-haiku-4-5-20251001")

  def initialize(extraction:, page_locator:, model: DEFAULT_MODEL, llm_client: nil)
    @extraction = extraction
    @page_locator = page_locator
    @model = model
    @llm_client = llm_client || method(:call_ruby_llm)
  end

  def apply(checks)
    claims = claims_for(checks)
    return checks unless eligible?(checks, claims)

    pages = claims.values.map { _1.fetch(:physical_page) }.uniq.sort
    page_map = pages.each_with_index.to_h { |page, index| [ page, index + 1 ] }
    prompt = build_prompt(claims, page_map)
    response = @page_locator.with_excerpt(pages) do |excerpt|
      raw = @llm_client.call(prompt:, pdf_path: excerpt.to_s)
      raw.respond_to?(:content) ? raw.content : raw
    end
    response = JSON.parse(response) if response.is_a?(String)
    apply_response(checks, claims, page_map, response)
  rescue => error
    [ *checks, check("visual_evidence:verifier", "fail", "#{error.class}: #{error.message}") ]
  end

  private

  def eligible?(checks, claims)
    failures = checks.select { _1[:status] == "fail" }
    failures.any? && failures.all? { claims.key?(_1[:id]) }
  end

  def claims_for(checks)
    failed_ids = checks.select { _1[:status] == "fail" }.pluck(:id)
    claims = {}
    @extraction.financial_statement_facts.each do |fact|
      id = "evidence:#{fact.concept}"
      next unless id.in?(failed_ids)

      claims[id] = {
        id:, kind: "fact", physical_page: fact.source_page, label: fact.raw_label,
        category: "", value: fact.value, scale: fact.scale, concept: fact.concept
      }
    end
    @extraction.financial_statement_line_items.each do |item|
      id = "line_evidence:#{line_item_key(item)}"
      next unless id.in?(failed_ids)

      claims[id] = {
        id:, kind: "line_item", physical_page: item.source_page, label: item.label,
        category: item.category, value: item.value, scale: item.scale, concept: nil
      }
    end
    claims
  end

  def build_prompt(claims, page_map)
    requests = claims.values.map do |claim|
      <<~CLAIM
        - id: #{claim.fetch(:id)}
          kind: #{claim.fetch(:kind)}
          target label: #{claim.fetch(:label)}
          target category: #{claim.fetch(:category).presence || "(none)"}
          excerpt page: #{page_map.fetch(claim.fetch(:physical_page))}
      CLAIM
    end.join
    <<~PROMPT
      Independently transcribe cited current-year cells from the attached Canadian municipal financial statement excerpt.
      Fiscal year: #{@extraction.fiscal_year_end.year}

      For every request below, inspect only its stated excerpt page. Return the exact printed label, category (or an empty
      string for facts), current-year actual numeric cell, printed column-year heading, and excerpt page. Mark found=false
      if the row or exact current-year cell is absent, ambiguous, illegible, budget-only, or comparative-only. Never calculate,
      infer, substitute a total, or copy a value from another column. Do not omit a request.

      REQUESTS
      #{requests}
    PROMPT
  end

  def apply_response(checks, claims, page_map, response)
    rows = response.fetch("claims")
    raise ArgumentError, "visual claims must be an array" unless rows.is_a?(Array)
    ids = rows.map { _1.fetch("id") }
    raise ArgumentError, "visual claim ids must be unique" unless ids.uniq.length == ids.length
    raise ArgumentError, "visual claim ids do not match requests" unless ids.sort == claims.keys.sort

    verdicts = rows.to_h do |row|
      claim = claims.fetch(row.fetch("id"))
      [ claim.fetch(:id), verify_claim(claim, page_map, row) ]
    end
    updated = checks.map do |existing|
      verdict = verdicts[existing[:id]]
      verdict&.fetch(:passed) ? check(existing[:id], "pass", verdict.fetch(:detail)) : existing
    end
    visual_checks = verdicts.map do |id, verdict|
      check("visual_evidence:#{id}", verdict.fetch(:passed) ? "pass" : "fail", verdict.fetch(:detail))
    end
    [ *updated, *visual_checks ]
  end

  def verify_claim(claim, page_map, row)
    expected_excerpt = page_map.fetch(claim.fetch(:physical_page))
    failures = []
    failures << "not found or ambiguous" unless row.fetch("found")
    failures << "wrong excerpt page" unless Integer(row.fetch("excerpt_page")) == expected_excerpt
    failures << "label mismatch" unless evidence_key(row.fetch("transcribed_label")) == evidence_key(claim.fetch(:label))
    if claim.fetch(:kind) == "line_item"
      failures << "category mismatch" unless evidence_key(row.fetch("transcribed_category")) == evidence_key(claim.fetch(:category))
    end
    column_year = row.fetch("column_year").to_s
    current_year = @extraction.fiscal_year_end.year.to_s
    failures << "wrong year or non-actual column" unless column_year.match?(/(?<!\d)#{Regexp.escape(current_year)}(?!\d)/) &&
      !column_year.match?(/budget|budg[eé]taire|comparative?/i)
    transcribed = Warehouse::FinancialStatementExtraction::NumberParser.parse(
      row.fetch("raw_text"), raw_label: row.fetch("transcribed_label"), concept: claim.fetch(:concept)
    ) * Integer(claim.fetch(:scale))
    failures << "value mismatch" unless transcribed == BigDecimal(claim.fetch(:value).to_s)
    detail = if failures.empty?
      "visual model=#{@model}; physical_page=#{claim.fetch(:physical_page)}; " \
        "raw_text=#{row.fetch('raw_text').inspect}; column_year=#{column_year.inspect}"
    else
      "visual model=#{@model}; physical_page=#{claim.fetch(:physical_page)}; #{failures.join(', ')}"
    end
    { passed: failures.empty?, detail: }
  rescue KeyError, ArgumentError, Warehouse::FinancialStatementExtraction::NumberParser::ParseError => error
    { passed: false, detail: "visual model=#{@model}; physical_page=#{claim.fetch(:physical_page)}; #{error.message}" }
  end

  def call_ruby_llm(prompt:, pdf_path:)
    RubyLLM.chat(model: @model)
      .with_temperature(0)
      .with_schema(Warehouse::FinancialStatementExtraction::VisualEvidenceResponseSchema)
      .ask(prompt, with: pdf_path)
  end

  def line_item_key(item)
    [ item.flow, item.category, item.label ].join(":").parameterize
  end

  def evidence_key(value) = value.to_s.parameterize
  def check(id, status, detail) = { id:, status:, detail: }
end
