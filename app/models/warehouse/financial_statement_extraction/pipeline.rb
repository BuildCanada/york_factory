require "timeout"

class Warehouse::FinancialStatementExtraction::Pipeline
  EXTRACTOR_VERSION = "headline-psas-v1"
  DEFAULT_MODEL = "gemini-3-flash-preview"
  MODEL_TIMEOUT = 180
  Result = Data.define(:status, :facts, :checks, :prompt, :response, :locator_result, :language, :statement_basis)

  class ResponseError < StandardError; end

  def initialize(pdf_path:, institution_canonical_id:, institution_name:, document_canonical_id:,
    asset_sha256:, fiscal_year_end:, population: nil, model: DEFAULT_MODEL, llm_client: nil,
    page_locator: nil)
    @pdf_path = Pathname(pdf_path)
    @institution_canonical_id = institution_canonical_id
    @institution_name = institution_name
    @document_canonical_id = document_canonical_id
    @asset_sha256 = asset_sha256
    @fiscal_year_end = fiscal_year_end.to_date
    @population = population
    @model = model
    @llm_client = llm_client || method(:call_ruby_llm)
    @page_locator = page_locator || Warehouse::FinancialStatementExtraction::PageLocator.new(@pdf_path)
  end

  def run
    verify_source_hash!
    locator_result = @page_locator.locate
    prompt = build_prompt(locator_result)
    raw_response = nil
    response = nil
    @page_locator.with_excerpt(locator_result.candidate_pages) do |excerpt|
      raw_response = Timeout.timeout(MODEL_TIMEOUT) { @llm_client.call(prompt:, pdf_path: excerpt.to_s) }
      response = raw_response.respond_to?(:content) ? raw_response.content : raw_response
    end
    response = JSON.parse(response) if response.is_a?(String)
    validate_response!(response, locator_result)
    facts = normalize_facts(response.fetch("facts"), locator_result)
    validator = Warehouse::FinancialStatementExtraction::Validator.new(
      facts:, fiscal_year: @fiscal_year_end.year, population: @population,
      page_texts: locator_result.page_texts,
      flags: {
        remeasurement_present: response.fetch("remeasurement_present"),
        operations_adjustment_present: response.fetch("operations_adjustment_present"),
        rollforward_adjustment_present: response.fetch("rollforward_adjustment_present")
      }
    )
    checks = [ source_identity_check, *validator.validate ]
    status = validator.acceptable?(checks) ? "extracted" : "needs_review"
    Result.new(status:, facts:, checks:, prompt:, response:, locator_result:,
      language: response.fetch("language"), statement_basis: response.fetch("statement_basis"))
  rescue JSON::ParserError, KeyError, ArgumentError, ResponseError, Timeout::Error => error
    raise ResponseError, error.message
  end

  private

  def source_identity_check
    {
      id: "source_identity",
      status: "pass",
      detail: "document=#{@document_canonical_id}; asset_sha256=#{@asset_sha256}"
    }
  end

  def verify_source_hash!
    raise ResponseError, "missing source PDF #{@pdf_path}" unless @pdf_path.file?
    actual = Digest::SHA256.file(@pdf_path).hexdigest
    raise ResponseError, "asset SHA mismatch: expected #{@asset_sha256}, got #{actual}" unless actual == @asset_sha256
  end

  def call_ruby_llm(prompt:, pdf_path:)
    RubyLLM.chat(model: @model)
      .with_temperature(0)
      .with_schema(Warehouse::FinancialStatementExtraction::ResponseSchema)
      .ask(prompt, with: pdf_path)
  end

  def build_prompt(locator_result)
    page_map = locator_result.candidate_pages.map.with_index(1) do |physical, excerpt|
      "excerpt page #{excerpt} = archived PDF physical page #{physical}"
    end.join("\n")
    <<~PROMPT
      Extract headline Canadian public-sector accounting totals from the attached excerpt.

      Expected institution: #{@institution_name} (#{@institution_canonical_id})
      Expected document: #{@document_canonical_id}
      Expected fiscal year: #{@fiscal_year_end.year}

      PAGE MAP
      #{page_map}

      Rules:
      - Extract only the expected fiscal year's ACTUAL column. Never use budget or comparative columns.
      - Return only totals explicitly printed in the attached primary statements. Never calculate or infer a missing fact.
      - A section total may be printed on an unlabeled line immediately before the next heading. In that case, use the section heading (for example "Revenues") as raw_label and the printed total as raw_text.
      - Preserve raw_label and raw_text exactly as printed.
      - scale is exactly 1, 1000, or 1000000 and must follow the printed heading.
      - Preserve parentheses and minus signs in raw_text. The deterministic parser applies signs and scale.
      - excerpt_page refers to the attached excerpt, not a printed footer page number.
      - column_year must preserve the exact current-year column heading.
      - If a concept is absent or ambiguous, omit it. Do not guess.
      - statement_basis is consolidated unless the statement explicitly says otherwise.
      - rollforward_adjustment_present is true when remeasurement, restatement, other comprehensive income, or another printed adjustment prevents opening surplus plus annual surplus from equalling closing surplus.
      - remeasurement_present is true when the financial-position statement separately presents accumulated remeasurement gains or losses.
      - operations_adjustment_present is true when separately printed items such as capital contributions, transfers, gains, or losses occur between total revenue less total expenses and annual surplus.
      - rollforward_adjustment_present concerns the expected fiscal year's actual rollforward only, not a prior-year comparative adjustment.

      Allowed concepts:
      total_financial_assets, total_liabilities, net_financial_assets,
      total_non_financial_assets, accumulated_surplus, opening_accumulated_surplus,
      total_revenue, total_expenses, annual_surplus.

      Recognize equivalent French labels, including actifs financiers, passifs, dette nette,
      actifs non financiers, excédent accumulé, revenus, charges, and excédent de l'exercice.
    PROMPT
  end

  def validate_response!(response, locator_result)
    raise ResponseError, "response must be an object" unless response.is_a?(Hash)
    raise ResponseError, "response fiscal year does not match #{@fiscal_year_end.year}" unless Integer(response.fetch("fiscal_year")) == @fiscal_year_end.year
    raise ResponseError, "invalid language" unless response.fetch("language").in?(Warehouse::FinancialStatementExtraction::LANGUAGES)
    raise ResponseError, "invalid statement basis" unless response.fetch("statement_basis").in?(Warehouse::FinancialStatementExtraction::STATEMENT_BASES)
    raise ResponseError, "facts must be a non-empty array" unless response.fetch("facts").is_a?(Array) && response.fetch("facts").any?

    concepts = response.fetch("facts").map { |fact| fact.fetch("concept") }
    raise ResponseError, "duplicate concepts in response" unless concepts.uniq.length == concepts.length
    response.fetch("facts").each do |fact|
      raise ResponseError, "invalid concept #{fact['concept'].inspect}" unless fact.fetch("concept").in?(Warehouse::FinancialStatementFact::CONCEPTS)
      raise ResponseError, "invalid statement #{fact['statement'].inspect}" unless fact.fetch("statement").in?(Warehouse::FinancialStatementFact::STATEMENTS)
      raise ResponseError, "invalid scale #{fact['scale'].inspect}" unless Integer(fact.fetch("scale")).in?(Warehouse::FinancialStatementFact::SCALES)
      excerpt_page = Integer(fact.fetch("excerpt_page"))
      raise ResponseError, "excerpt page #{excerpt_page} is out of range" unless excerpt_page.between?(1, locator_result.candidate_pages.length)
      confidence = Float(fact.fetch("confidence"))
      raise ResponseError, "confidence out of range" unless confidence.between?(0, 1)
    end
  end

  def normalize_facts(raw_facts, locator_result)
    raw_facts.map do |fact|
      {
        concept: fact.fetch("concept"),
        statement: fact.fetch("statement"),
        raw_label: fact.fetch("raw_label"),
        raw_text: fact.fetch("raw_text"),
        value: Warehouse::FinancialStatementExtraction::NumberParser.parse(
          fact.fetch("raw_text"), raw_label: fact.fetch("raw_label"), concept: fact.fetch("concept")
        ) * Integer(fact.fetch("scale")),
        scale: Integer(fact.fetch("scale")),
        source_page: locator_result.candidate_pages.fetch(Integer(fact.fetch("excerpt_page")) - 1),
        column_year: fact.fetch("column_year"),
        extraction_confidence: BigDecimal(fact.fetch("confidence").to_s)
      }
    end
  end
end
