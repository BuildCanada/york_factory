class Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline
  PARSER_VERSION = "prairie-municipal-form-v3"
  REVIEWABLE_PARSER_VERSIONS = [
    PARSER_VERSION, "prairie-municipal-form-v2", "prairie-municipal-form-v1",
    "saskatchewan-municipal-form-v1"
  ].freeze
  Unsupported = Class.new(StandardError)
  Result = Warehouse::FinancialStatementExtraction::DetailedPipeline::Result
  Headline = Data.define(:pipeline) do
    def run = pipeline.run_headline
  end
  EXPENSE_HEADING_PATTERN = /\A(?:EXPENSES?|EXPENDITURES)\b/i

  FACT_LABELS = {
    total_financial_assets: /\A(?:Total )?Financial Assets\b/i,
    total_liabilities: /\ATotal\s+Liabi\s*lities\b/i,
    net_financial_assets: /\ANET (?:FINANCIAL ASSETS(?: \(DEBT\))?|DEBT)\b/i,
    total_non_financial_assets: /\A(?:Total )?Non-Financial Assets\b/i,
    accumulated_surplus: /\AACCUMULATED SURPLUS(?: \(DEFICIT\))?/i,
    total_revenue: /\ATotal Revenues?\b/i,
    total_expenses: /\ATotal (?:Operating )?(?:Expenses?|Expenditures)\b/i,
    opening_accumulated_surplus: /\AAccumulated Surplus(?: \(Deficit\))?,?\s+(?:at )?Beginning of Year\b/i
  }.freeze
  ANNUAL_SURPLUS_PATTERN = /\A(?:Annual Surplus|Surplus \(Deficit\) of Revenues over (?:Expenses?|Expenditures)|Excess \((?:Deficiency|Shortfall)\) of Revenues? over Expenses?|Excess of (?:Revenue over Expenses?|Expenses? over Revenue)|Excess revenues \(expenses\)).*\z/i
  POSITION_SECTIONS = {
    total_financial_assets: [ /\AFINANCIAL ASSETS\b/i, /\A(?:FINANCIAL )?LIABI\s*LITIES\b/i ],
    total_liabilities: [ /\A(?:FINANCIAL )?LIABI\s*LITIES\b/i, /\A(?:NET (?:FINANCIAL ASSETS|DEBT)|NON-FINANCIAL ASSETS)\b/i ],
    total_non_financial_assets: [ /\ANON-FINANCIAL ASSETS\b/i, /\AACCUMULATED SURPLUS\b/i ]
  }.freeze
  POSITION_SECTION_LABELS = {
    total_financial_assets: "FINANCIAL ASSETS",
    total_liabilities: "LIABILITIES",
    total_non_financial_assets: "NON-FINANCIAL ASSETS"
  }.freeze

  def self.applicable?(institution_canonical_id:, **)
    institution_canonical_id.start_with?("ca/sk/", "ca/ab/", "ca/bc/", "ca/ns/")
  end

  def initialize(pdf_path:, institution_canonical_id:, document_canonical_id:, asset_sha256:,
    fiscal_year_end:, population: nil, page_locator: nil, **)
    @pdf_path = Pathname(pdf_path)
    @institution_canonical_id = institution_canonical_id
    @document_canonical_id = document_canonical_id
    @asset_sha256 = asset_sha256
    @fiscal_year = fiscal_year_end.year
    @population = population
    @page_locator = page_locator || Warehouse::FinancialStatementExtraction::PageLocator.new(
      @pdf_path, max_ocr_pages: 8
    )
  end

  def run
    verify_source!
    located = enrich_with_table_ocr(@page_locator.locate)
    parse_located(located)
  rescue Unsupported => error
    raise error unless located && !located.ocr_pages.include?(located.operations_page)

    parse_located(with_operations_table_ocr(located))
  rescue Warehouse::FinancialStatementExtraction::PageLocator::LocationError => error
    raise Unsupported, error.message
  end

  def run_headline
    detailed = run
    flags = detailed.response.fetch("headline")
    Warehouse::FinancialStatementExtraction::Pipeline::Result.new(
      status: detailed.status, facts: detailed.facts, checks: detailed.checks,
      prompt: nil, response: flags.merge(
        "parser" => PARSER_VERSION, "fiscal_year" => @fiscal_year,
        "language" => detailed.language, "statement_basis" => detailed.statement_basis
      ),
      locator_result: detailed.locator_result, language: detailed.language,
      statement_basis: detailed.statement_basis
    )
  end

  private

  def parse_located(located)
    operations = EnglishPage.new(located.page_texts.fetch(located.operations_page), fiscal_year: @fiscal_year, kind: :operations)
    position = EnglishPage.new(located.page_texts.fetch(located.position_page), fiscal_year: @fiscal_year, kind: :position)
    @scale = Warehouse::FinancialStatementExtraction::ScaleDetector.detect(
      located.page_texts.values_at(located.operations_page, located.position_page)
    )
    facts = build_facts(operations, position, located)
    fallbacks = facts.filter_map do |fact|
      confidence = fact.fetch(:extraction_confidence)
      next unless confidence < 1

      {
        "concept" => fact.fetch(:concept),
        "type" => confidence == BigDecimal("0.90") ? "single_component" : "unlabeled_section_total"
      }
    end
    line_items = build_line_items(operations, located.operations_page)
    flags = flags_for(operations, position, facts)
    validator = Warehouse::FinancialStatementExtraction::Validator.new(
      facts:, line_items:, fiscal_year: @fiscal_year, population: @population,
      page_texts: located.page_texts, flags:
    )
    checks = [ source_check, *validator.validate ]
    if fallbacks.any? { _1.fetch("type") == "single_component" }
      position_surplus = checks.find { _1[:id] == "position_surplus" }
      checks << {
        id: "position_single_component",
        status: position_surplus&.fetch(:status) == "pass" ? "pass" : "fail",
        detail: "single-component total requires a passing, non-skipped position surplus identity"
      }
    end
    failures = checks.select { _1[:status] == "fail" }.map { _1[:id] }
    raise Unsupported, "municipal form failed deterministic validation: #{failures.join(', ')}" unless validator.acceptable?(checks)

    response = {
      "parser" => PARSER_VERSION,
      "headline" => flags.stringify_keys,
      "details" => {
        "source" => "standardized Canadian municipal financial statement",
        "position_total_fallbacks" => fallbacks
      }
    }
    Result.new(
      status: "extracted", facts:, line_items:, checks:, prompt: nil, response:,
      locator_result: located, language: "en", statement_basis: "consolidated"
    )
  rescue Warehouse::FinancialStatementExtraction::NumberParser::ParseError,
    KeyError, ArgumentError => error
    raise Unsupported, error.message
  end

  def with_operations_table_ocr(located)
    page = located.operations_page
    located.with(
      page_texts: located.page_texts.merge(page => @page_locator.ocr_table_page(page)),
      ocr_pages: (located.ocr_pages + [ page ]).uniq.sort
    )
  rescue Warehouse::FinancialStatementExtraction::PageLocator::LocationError => error
    raise Unsupported, error.message
  end

  def verify_source!
    raise Unsupported, "missing source PDF" unless @pdf_path.file?
    raise Unsupported, "asset SHA mismatch" unless Digest::SHA256.file(@pdf_path).hexdigest == @asset_sha256
  end

  def enrich_with_table_ocr(located)
    required = {
      located.position_page => FACT_LABELS.values_at(
        :total_financial_assets, :total_liabilities, :net_financial_assets,
        :total_non_financial_assets, :accumulated_surplus
      ),
      located.operations_page => [
        FACT_LABELS.fetch(:total_revenue), FACT_LABELS.fetch(:total_expenses), annual_surplus_pattern
      ]
    }
    replacements = required.filter_map do |page, _patterns|
      text = located.page_texts.fetch(page)
      if page == located.position_page
        next if position_values_complete?(text)

        table_text = @page_locator.ocr_table_page(page)
        next unless position_values_complete?(table_text)

        next [ page, table_text ]
      end
      next if operations_values_complete?(text)

      table_text = @page_locator.ocr_table_page(page)
      next unless operations_values_complete?(table_text)

      [ page, table_text ]
    end.to_h
    return located if replacements.empty?

    located.with(
      page_texts: located.page_texts.merge(replacements),
      ocr_pages: (located.ocr_pages + replacements.keys).uniq.sort
    )
  end

  def position_values_complete?(text)
    page = EnglishPage.new(text, fiscal_year: @fiscal_year, kind: :position)
    FACT_LABELS.slice(
      :total_financial_assets, :total_liabilities, :net_financial_assets,
      :total_non_financial_assets, :accumulated_surplus
    ).all? do |concept, pattern|
      entry = page.find(pattern)
      entry = nil if entry && null?(entry[:current])
      entry ||= position_total(page, concept)
      entry.present?
    end
  rescue Unsupported, ArgumentError
    false
  end

  def operations_values_complete?(text)
    page = EnglishPage.new(text, fiscal_year: @fiscal_year, kind: :operations)
    totals = FACT_LABELS.slice(:total_revenue, :total_expenses).map do |concept, pattern|
      entry = page.find(pattern)
      entry = nil if entry && null?(entry[:current])
      entry || operation_total(page, concept)
    end
    entries = [ *totals, annual_surplus_entry(page) ]
    return false if entries.any?(&:nil?)

    entries.all? do |entry|
      current = entry[:current]
      next false if current.blank? || null?(current)

      parse(current)
      true
    end
  rescue Unsupported, ArgumentError, Warehouse::FinancialStatementExtraction::NumberParser::ParseError
    false
  end

  def source_check
    { id: "source_identity", status: "pass", detail: "document=#{@document_canonical_id}; asset_sha256=#{@asset_sha256}" }
  end

  def build_facts(operations, position, located)
    facts = FACT_LABELS.filter_map do |concept, pattern|
      page = concept.in?(%i[total_financial_assets total_liabilities net_financial_assets total_non_financial_assets accumulated_surplus]) ? position : operations
      statement = if concept.in?(%i[opening_accumulated_surplus accumulated_surplus])
        "accumulated_surplus"
      elsif page == position
        "financial_position"
      else
        "operations"
      end
      entry = page.find(pattern)
      entry = nil if entry && null?(entry[:current])
      entry ||= operation_total(operations, concept) if page == operations
      entry ||= position_total(position, concept) if page == position
      next if concept == :opening_accumulated_surplus && entry.nil?

      raise Unsupported, "row not found: #{pattern.inspect}" unless entry
      fact(concept, entry, page == position ? located.position_page : located.operations_page, statement)
    end
    annual = annual_surplus_entry(operations)
    raise Unsupported, "final annual surplus row not found" unless annual

    facts << fact(:annual_surplus, annual, located.operations_page, "operations")
    facts
  end

  def operation_total(operations, concept)
    case concept
    when :total_revenue
      row = operations.section(/\AREVENUES?\b/i, EXPENSE_HEADING_PATTERN)
        .reverse.find { _1[:label].blank? && _1[:current].present? && !null?(_1[:current]) }
      heading = operations.find(/\AREVENUES?\b/i)&.fetch(:label)
      row&.merge(label: heading || "Revenue", extraction_confidence: BigDecimal("0.95"))
    when :total_expenses
      rows = operations.section(EXPENSE_HEADING_PATTERN, annual_surplus_pattern)
      row = rows.reverse.find { _1[:label].blank? && _1[:current].present? && !null?(_1[:current]) }
      heading = operations.find(EXPENSE_HEADING_PATTERN)&.fetch(:label)
      row&.merge(label: heading || "Expenses", extraction_confidence: BigDecimal("0.95"))
    end
  end

  def annual_surplus_entry(operations)
    rows = operations.lines.reverse.select { _1[:label].match?(annual_surplus_pattern) }
    rows.find { _1[:current].present? && !null?(_1[:current]) } || rows.first
  end

  def position_total(position, concept)
    boundaries = POSITION_SECTIONS[concept]
    return unless boundaries

    rows = position.section(*boundaries)
    component_rows = rows.select do |row|
      row[:label].to_s.match?(/[[:alnum:]]/) && row[:current].present? && !null?(row[:current])
    end
    row = rows.reverse.find do |candidate|
      !candidate[:label].to_s.match?(/[[:alnum:]]/) &&
        candidate[:current].present? && !null?(candidate[:current])
    end
    if component_rows.length >= 2 && row
      return row.merge(
        label: POSITION_SECTION_LABELS.fetch(concept),
        extraction_confidence: BigDecimal("0.95")
      )
    end
    return unless concept == :total_non_financial_assets && component_rows.one? && row.nil?

    component_rows.first.merge(extraction_confidence: BigDecimal("0.90"))
  end

  def fact(concept, entry, source_page, statement)
    raw_label = entry.fetch(:label)
    raw_text = entry.fetch(:current)
    {
      concept: concept.to_s, statement:, raw_label:, raw_text:,
      value: parse(raw_text, raw_label:, concept: concept.to_s) * @scale, scale: @scale,
      source_page:, column_year: entry.fetch(:column_year),
      extraction_confidence: entry.fetch(:extraction_confidence, BigDecimal("1"))
    }
  rescue Warehouse::FinancialStatementExtraction::NumberParser::ParseError => error
    raise Unsupported, "#{concept}: #{error.message}"
  end

  def build_line_items(operations, source_page)
    revenue = operations.section(/\AREVENUES?\b/i, EXPENSE_HEADING_PATTERN)
    expenses = operations.section(
      EXPENSE_HEADING_PATTERN,
      Regexp.union(/\ATotal (?:Operating )?(?:Expenses?|Expenditures)\b/i, annual_surplus_pattern)
    )
    revenue.reject! { _1[:label].blank? || _1[:label].match?(/\ATotal Revenues?\b/i) }
    expenses.reject! { _1[:label].blank? || _1[:label].match?(/\ATotal (?:Expenses?|Expenditures)\b/i) }
    revenue |= capital_rows(operations)
    positions = Hash.new(0)
    [ [ "revenue", revenue ], [ "expense", expenses ] ].flat_map do |flow, rows|
      rows.filter_map do |entry|
        next if entry[:current].blank? || null?(entry[:current])

        label = entry.fetch(:label)
        item = {
          flow:, category: label, label:, raw_text: entry.fetch(:current),
          value: parse(entry.fetch(:current)) * @scale, scale: @scale, source_page:,
          column_year: entry.fetch(:column_year), position: positions[flow],
      extraction_confidence: entry.fetch(:extraction_confidence, BigDecimal("1"))
        }
        positions[flow] += 1
        item
      end
    end
  end

  def flags_for(operations, position, facts)
    capital = capital_rows(operations).first
    facts_by_concept = facts.index_by { _1.fetch(:concept) }
    operations_discrepancy = facts_by_concept.fetch("total_revenue").fetch(:value) -
      facts_by_concept.fetch("total_expenses").fetch(:value) -
      facts_by_concept.fetch("annual_surplus").fetch(:value)
    remeasurement = position.lines.any? do |line|
      line[:label].match?(/remeasurement/i) && line[:current].present? && !null?(line[:current])
    end
    {
      remeasurement_present: remeasurement,
      operations_adjustment_present: operations_discrepancy.nonzero? &&
        capital && capital[:current].present? && !null?(capital[:current]),
      rollforward_adjustment_present: remeasurement
    }
  end

  def null?(value) = Warehouse::FinancialStatementExtraction::NumberParser.null_marker?(value)

  def capital_rows(operations)
    operations.lines.select do |line|
      line[:label].match?(/\A(?:.*Capital Grants and Contributions|Other Capital Contributions|.*transfers for capital|Contributed assets)\b/i) &&
        line[:current].present? && !null?(line[:current])
    end
  end

  def annual_surplus_pattern
    ANNUAL_SURPLUS_PATTERN
  end

  def parse(raw_text, raw_label: nil, concept: nil)
    Warehouse::FinancialStatementExtraction::NumberParser.parse(raw_text, raw_label:, concept:)
  end

  class EnglishPage
    NUMBER = /\(?-?(?:\d \d{1,2}[,.]\d{3}|\d{1,3}(?:[,.]\d{3})+|\d+)\)?|(?<![[:alnum:]])[-=](?![[:alnum:]])/.freeze
    attr_reader :lines

    def initialize(text, fiscal_year:, kind:)
      @fiscal_year = fiscal_year
      @kind = kind
      @expected_columns, @current_column, @column_year = locate_columns(text)
      @lines = parse_lines(text)
    end

    def fetch(pattern)
      find(pattern) || raise(Unsupported, "row not found: #{pattern.inspect}")
    end

    def find(pattern)
      matches = lines.select { _1[:label].match?(pattern) }
      matches.find { _1[:current].present? } || matches.first
    end

    def between(start_pattern, finish_pattern)
      section(start_pattern, finish_pattern)
    end

    def section(start_pattern, finish_pattern)
      start_index = lines.index { _1[:label].match?(start_pattern) }
      raise Unsupported, "section not found: #{start_pattern.inspect}" unless start_index

      finish_index = lines.each_index.find do |index|
        index > start_index && lines[index][:label].match?(finish_pattern)
      end
      raise Unsupported, "section total not found: #{finish_pattern.inspect}" unless finish_index

      lines[(start_index + 1)...finish_index]
    end

    private

    def locate_columns(text)
      candidates = text.lines.filter_map do |line|
        years = line.scan(/(?<!\d)(?:19|20)\d{2}(?!\d)/)
        next unless years.include?(@fiscal_year.to_s) && years.length >= 2

        budget = @kind == :operations && line.match?(/budget|fiscal plan/i)
        expected = years.length + (budget && years.count(@fiscal_year.to_s) == 1 ? 1 : 0)
        current = if budget || years.count(@fiscal_year.to_s) > 1
          1
        else
          years.index(@fiscal_year.to_s)
        end
        [ expected, current, @fiscal_year.to_s, line ]
      end
      selected = candidates.max_by { |expected, _, _, line| [ expected, line.length ] }
      unless selected
        years = text.lines.filter_map do |line|
          stripped = line.strip
          stripped if stripped.match?(/\A(?:19|20)\d{2}\z/)
        end
        if years.include?(@fiscal_year.to_s) && years.length >= 2
          selected = [ years.length, years.index(@fiscal_year.to_s), @fiscal_year.to_s ]
        end
      end
      selected ||= infer_standard_columns(text)
      raise Unsupported, "current-year column layout not found" unless selected

      selected.first(3)
    end

    def infer_standard_columns(text)
      title = @kind == :operations ? /Statement of Operations/i : /Statement of Financial Position/i
      return unless text.match?(title) && text.match?(/(?<!\d)#{@fiscal_year}(?!\d)/)

      counts = text.lines.filter_map do |line|
        without_references = line.gsub(/\([^)]*(?:schedule|note)[^)]*\)/i, "")
        numeric = without_references.scan(NUMBER).count do |token|
          token.in?(%w[- =]) || token.count("0-9") >= 2
        end
        numeric if numeric.in?([ 2, 3 ])
      end
      expected, occurrences = counts.tally.max_by { |columns, frequency| [ frequency, columns ] }
      return unless occurrences.to_i >= 3
      return if @kind == :position && expected != 2

      current = @kind == :operations && expected == 3 ? 1 : 0
      [ expected, current, @fiscal_year.to_s ]
    end

    def parse_lines(text)
      pending_labels = []
      text.lines.filter_map do |raw_line|
        if raw_line.strip.blank?
          pending_labels.clear
          next
        end

        row = parse_line(raw_line.chomp)
        unless row
          pending_labels.clear
          next
        end
        if row[:current].blank?
          label = row.fetch(:label)
          if FACT_LABELS.values.any? { label.match?(_1) }
            pending_labels.replace([ label ])
          else
            pending_labels << label
          end
          pending_labels.shift while pending_labels.length > 3
          next row
        end

        if row.fetch(:label).blank? &&
            Warehouse::FinancialStatementExtraction::NumberParser.null_marker?(row.fetch(:current))
          next row
        end

        combined_label = [ *pending_labels, row.fetch(:label) ].join(" ").squish
        pending_labels.clear
        if wrapped_label?(combined_label, current_label: row.fetch(:label))
          row.merge(label: combined_label)
        else
          row
        end
      end
    end

    def wrapped_label?(label, current_label:)
      label.match?(ANNUAL_SURPLUS_PATTERN) ||
        (current_label.blank? && FACT_LABELS.values.any? { label.match?(_1) })
    end

    def parse_line(line)
      stripped = line.strip
      return if stripped.blank?
      return if column_header?(stripped)
      if stripped.match?(/\A(?:REVENUES?|EXPENSES?|EXPENDITURES)(?:\s+\(unaudited\))?\z/i)
        return { label: stripped, current: nil, column_year: @column_year }
      end

      scannable = stripped.gsub(/\([^)]*(?:schedule|note)[^)]*\)/i) { " " * _1.length }
      matches = scannable.to_enum(:scan, NUMBER).map { [ Regexp.last_match[0], Regexp.last_match.begin(0) ] }
      numeric = matches.select { |token, _| token.in?(%w[- =]) || token.count("0-9") >= 2 }
      return { label: stripped, current: nil, column_year: @column_year } if numeric.length < 2

      return { label: stripped, current: nil, column_year: @column_year } if numeric.length < @expected_columns

      if numeric.length == @expected_columns + 1
        previous_token, previous_start = numeric[-2]
        fragment, fragment_start = numeric[-1]
        separator = stripped[(previous_start + previous_token.length)...fragment_start]
        if fragment.count("0-9").between?(1, 2) &&
            !Warehouse::FinancialStatementExtraction::NumberParser.null_marker?(fragment) &&
            !fragment.match?(/\A(?:19|20)\d{2}\z/) && separator.match?(/\A[,.]\z/)
          numeric.pop
        end
      end

      while numeric.length > @expected_columns &&
          Warehouse::FinancialStatementExtraction::NumberParser.null_marker?(numeric.last.first)
        surviving = numeric[-(@expected_columns + 1), @expected_columns]
        break unless surviving&.none? do |token, _position|
          Warehouse::FinancialStatementExtraction::NumberParser.null_marker?(token) ||
            token.match?(/\A(?:19|20)\d{2}\z/)
        end

        numeric.pop
      end

      columns = numeric.last(@expected_columns)
      label_end = columns.first.last
      { label: stripped[0...label_end].strip, current: columns.fetch(@current_column).first, column_year: @column_year }
    end

    def column_header?(text)
      remainder = text
        .gsub(/(?<!\d)(?:19|20)\d{2}(?!\d)/, " ")
        .gsub(/\b(?:budget|fiscal plan|actual|unaudited|audited)\b/i, " ")
      remainder.strip.blank?
    end
  end
end
