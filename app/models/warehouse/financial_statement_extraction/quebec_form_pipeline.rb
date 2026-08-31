class Warehouse::FinancialStatementExtraction::QuebecFormPipeline
  PARSER_VERSION = "quebec-mamh-form-v1"
  Result = Warehouse::FinancialStatementExtraction::DetailedPipeline::Result
  Unsupported = Class.new(StandardError)
  Headline = Data.define(:pipeline) do
    def run = pipeline.run_headline
  end

  OPERATIONS_TOTAL_ROWS = {
    total_revenue: 13,
    total_expenses: 24,
    annual_surplus: 25,
    opening_accumulated_surplus: 28,
    accumulated_surplus: 29
  }.freeze
  POSITION_ROWS_BY_YEAR = {
    (..2019) => {
      total_financial_assets: 8, total_liabilities: 15,
      net_financial_assets: 16, total_non_financial_assets: 21,
      accumulated_surplus: 22
    },
    2020 => {
      total_financial_assets: 8, total_liabilities: 16,
      net_financial_assets: 17, total_non_financial_assets: 22,
      accumulated_surplus: 23
    },
    (2021..) => {
      total_financial_assets: 8, total_liabilities: 16,
      net_financial_assets: 17, total_non_financial_assets: 23,
      accumulated_surplus: 24
    }
  }.freeze
  REVENUE_ROWS = (1..12)
  EXPENSE_ROWS = (14..23)
  SECTION_LABELS = {
    total_revenue: "Revenus",
    total_expenses: "Charges",
    total_financial_assets: "ACTIFS FINANCIERS",
    total_liabilities: "PASSIFS",
    total_non_financial_assets: "ACTIFS NON FINANCIERS"
  }.freeze

  def self.applicable?(institution_canonical_id:, fiscal_year_end:)
    institution_canonical_id.start_with?("ca/qc/") && fiscal_year_end.year >= 2016
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
      @pdf_path, max_ocr_pages: 0
    )
  end

  def run
    verify_source!
    located = prefer_mamh_form_pages(@page_locator.locate)
    operations = FormPage.new(located.page_texts.fetch(located.operations_page), @fiscal_year, current_column: 1)
    position = FormPage.new(located.page_texts.fetch(located.position_page), @fiscal_year, current_column: 0)
    operations, position, located = repair_mamh_table_ocr(operations, position, located)
    @scale = Warehouse::FinancialStatementExtraction::ScaleDetector.detect(
      located.page_texts.values_at(located.operations_page, located.position_page)
    )
    facts = build_facts(operations, position, located)
    line_items = build_line_items(operations, located.operations_page)
    flags = flags_for(operations, position)
    validator = Warehouse::FinancialStatementExtraction::Validator.new(
      facts:, line_items:, fiscal_year: @fiscal_year, population: @population,
      page_texts: located.page_texts, flags:
    )
    checks = [ source_check, *validator.validate ]
    raise Unsupported, failed_checks(checks) unless validator.acceptable?(checks)

    response = {
      "parser" => PARSER_VERSION,
      "headline" => flags.stringify_keys,
      "details" => {
        "source" => "Quebec standardized municipal financial report",
        "ocr_pages" => located.ocr_pages
      }
    }
    Result.new(
      status: "extracted", facts:, line_items:, checks:,
      prompt: nil, response:, locator_result: located,
      language: "fr", statement_basis: "consolidated"
    )
  rescue Warehouse::FinancialStatementExtraction::PageLocator::LocationError,
    Warehouse::FinancialStatementExtraction::NumberParser::ParseError,
    KeyError, ArgumentError => error
    raise Unsupported, error.message
  end

  def run_headline
    detailed = run
    flags = detailed.response.fetch("headline")
    Warehouse::FinancialStatementExtraction::Pipeline::Result.new(
      status: detailed.status, facts: detailed.facts, checks: detailed.checks,
      prompt: nil, response: flags.merge(
        "parser" => PARSER_VERSION,
        "fiscal_year" => @fiscal_year,
        "language" => detailed.language,
        "statement_basis" => detailed.statement_basis
      ),
      locator_result: detailed.locator_result, language: detailed.language,
      statement_basis: detailed.statement_basis
    )
  end

  private

  def prefer_mamh_form_pages(located)
    operations_pages = located.page_texts.filter_map do |page, text|
      page if text.match?(/Rapport financier.{0,30}\bS7\b/i)
    end
    return located unless operations_pages.one?

    operations_page = operations_pages.first
    position_page = operations_page + 1
    return located unless located.page_texts.key?(position_page)

    candidates = [ operations_page - 1, operations_page, position_page, position_page + 1 ]
      .select { _1.between?(1, located.page_count) }.uniq.sort
    located.with(operations_page:, position_page:, candidate_pages: candidates)
  end

  def verify_source!
    raise Unsupported, "missing source PDF" unless @pdf_path.file?
    actual = Digest::SHA256.file(@pdf_path).hexdigest
    raise Unsupported, "asset SHA mismatch" unless actual == @asset_sha256
  end

  def repair_mamh_table_ocr(operations, position, located)
    missing_operations = OPERATIONS_TOTAL_ROWS.values.reject { operations[_1] }
    missing_position = position_rows.values.reject { position[_1] }
    return [ operations, position, located ] if missing_operations.empty? && missing_position.empty?

    operations_ocr = @page_locator.ocr_table_page(located.operations_page)
    position_ocr = @page_locator.ocr_table_page(located.position_page)
    ocr_operations = OcrFormPage.new(operations_ocr, @fiscal_year, current_column: 1)
    ocr_position = OcrFormPage.new(position_ocr, @fiscal_year, current_column: 0)
    @ocr_operation_line_items = {
      "revenue" => ocr_operations.section_rows(/\ARevenus\b/i, /\ACharges\b/i),
      "expense" => ocr_operations.section_rows(/\ACharges\b/i, /\AExc[eé]dent\b/i)
    }

    repair_operation_rows(operations, ocr_operations, missing_operations)
    repair_position_rows(position, ocr_position, missing_position)
    remaining = OPERATIONS_TOTAL_ROWS.values.reject { operations[_1] } +
      position_rows.values.reject { position[_1] }
    raise Unsupported, "required MAMH rows missing after table OCR: #{remaining.join(', ')}" if remaining.any?

    page_texts = located.page_texts.merge(
      located.operations_page => [ located.page_texts.fetch(located.operations_page), operations_ocr ].join("\n"),
      located.position_page => [ located.page_texts.fetch(located.position_page), position_ocr ].join("\n")
    )
    repaired = located.with(
      page_texts:,
      ocr_pages: (located.ocr_pages + [ located.operations_page, located.position_page ]).uniq.sort
    )
    [ operations, position, repaired ]
  end

  def repair_operation_rows(page, ocr, missing)
    repairs = {
      13 => ocr.section_total(/\ARevenus\b/i, /\ACharges\b/i, label: "Revenus"),
      24 => ocr.section_total(/\ACharges\b/i, /\AExc[eé]dent\b/i, label: "Charges"),
      25 => ocr.label(/\AExc[eé]dent.*(?:de l['’]exercice|li[eé] aux activit[eé]s)/i),
      28 => ocr.label(/\ASolde redress[eé]\b/i),
      29 => ocr.label(/(?:fin de l['’]exercice|\AExc[eé]dent.*accumul[eé].*fin)/i)
    }
    missing.each { |row| page.put(row, repairs[row]) if repairs[row] }
  end

  def repair_position_rows(page, ocr, missing)
    rows = position_rows
    repairs = {
      rows.fetch(:total_financial_assets) => ocr.section_total(
        /\AACTIFS FINANCIERS\b/i, /\APASSIFS\b/i, label: "ACTIFS FINANCIERS"
      ),
      rows.fetch(:total_liabilities) => ocr.section_total(
        /\APASSIFS\b/i, /\AACTIFS FINANCIERS NETS|DETTE NETTE/i, label: "PASSIFS"
      ),
      rows.fetch(:net_financial_assets) => ocr.label(/ACTIFS FINANCIERS NETS|DETTE NETTE/i),
      rows.fetch(:total_non_financial_assets) => ocr.section_total(
        /\AACTIFS NON FINANCIERS\b/i, /EXC[EÉ]DENT.*ACCUMUL[EÉ]/i, label: "ACTIFS NON FINANCIERS"
      ),
      rows.fetch(:accumulated_surplus) => ocr.label(/\AEXC[EÉ]DENT.*ACCUMUL[EÉ]/i)
    }
    missing.each { |row| page.put(row, repairs[row]) if repairs[row] }
  end

  def source_check
    { id: "source_identity", status: "pass", detail: "document=#{@document_canonical_id}; asset_sha256=#{@asset_sha256}" }
  end

  def build_facts(operations, position, located)
    facts = []
    OPERATIONS_TOTAL_ROWS.each do |concept, row|
      entry = operations.fetch(row)
      facts << fact(concept, entry, located.operations_page,
        concept.in?(%i[opening_accumulated_surplus accumulated_surplus]) ? "accumulated_surplus" : "operations")
    end
    position_rows.each do |concept, row|
      entry = position.fetch(row)
      facts.reject! { |item| item[:concept] == concept.to_s }
      facts << fact(concept, entry, located.position_page, "financial_position")
    end
    facts
  end

  def fact(concept, entry, source_page, statement)
    raw_label = SECTION_LABELS.fetch(concept, entry.fetch(:label))
    {
      concept: concept.to_s, statement:, raw_label:,
      raw_text: entry.fetch(:raw_text),
      value: parse(entry.fetch(:raw_text), raw_label:, concept: concept.to_s) * @scale,
      scale: @scale, source_page:, column_year: entry.fetch(:column_year),
      extraction_confidence: BigDecimal("1")
    }
  end

  def build_line_items(operations, source_page)
    return build_ocr_line_items(source_page) if @ocr_operation_line_items

    positions = Hash.new(0)
    [ [ "revenue", REVENUE_ROWS ], [ "expense", EXPENSE_ROWS ] ].flat_map do |flow, rows|
      rows.filter_map do |row|
        entry = operations[row]
        next unless entry && entry[:raw_text].present?

        label = entry.fetch(:label)
        next if label.blank?
        result = {
          flow:, category: label, label:, raw_text: entry.fetch(:raw_text),
          value: parse(entry.fetch(:raw_text)) * @scale, scale: @scale, source_page:,
          column_year: entry.fetch(:column_year), position: positions[flow],
          extraction_confidence: BigDecimal("1")
        }
        positions[flow] += 1
        result
      end
    end
  end

  def build_ocr_line_items(source_page)
    @ocr_operation_line_items.flat_map do |flow, rows|
      rows.map.with_index do |entry, position|
        label = entry.fetch(:label)
        {
          flow:, category: label, label:, raw_text: entry.fetch(:raw_text),
          value: parse(entry.fetch(:raw_text)) * @scale, scale: @scale, source_page:,
          column_year: entry.fetch(:column_year), position:,
          extraction_confidence: BigDecimal("1")
        }
      end
    end
  end

  def flags_for(operations, position)
    {
      remeasurement_present: position.value_present?(26),
      operations_adjustment_present: false,
      rollforward_adjustment_present: operations.value_present?(27)
    }
  end

  def position_rows
    POSITION_ROWS_BY_YEAR.find do |year_or_range, _|
      year_or_range == @fiscal_year || year_or_range.respond_to?(:cover?) && year_or_range.cover?(@fiscal_year)
    end.last
  end

  def parse(raw_text, raw_label: nil, concept: nil)
    Warehouse::FinancialStatementExtraction::NumberParser.parse(raw_text, raw_label:, concept:)
  end

  def failed_checks(checks)
    failures = checks.select { |check| check[:status] == "fail" }.map { |check| check[:id] }
    "Quebec form did not pass deterministic validation: #{failures.join(', ')}"
  end

  class FormPage
    NUMBER = /\(?-?\d[\d ,.\u00A0\u202F]*\)?/

    def initialize(text, fiscal_year, current_column:)
      @text = text
      @fiscal_year = fiscal_year
      @preferred_current_column = current_column
      @column_starts = locate_columns
      @rows = parse_rows
    end

    def fetch(row) = @rows.fetch(row)
    def [](row) = @rows[row]
    def value_present?(row) = @rows[row]&.fetch(:raw_text).present?
    def put(row, entry) = @rows[row] ||= entry

    private

    def locate_columns
      candidates = @text.lines.filter_map do |line|
        current_year_starts = []
        line.to_enum(:scan, /(?<!\d)#{@fiscal_year}(?!\d)/).each { current_year_starts << Regexp.last_match.begin(0) }
        next if current_year_starts.empty?

        all_year_starts = []
        line.to_enum(:scan, /(?<!\d)(?:19|20)\d{2}(?!\d)/).each { all_year_starts << Regexp.last_match.begin(0) }
        [ all_year_starts.length, current_year_starts, all_year_starts, line ]
      end
      selected = candidates.max_by { |year_count, current, values, _| [ year_count, current.length, values.length ] }
      starts = selected&.third
      raise Unsupported, "current-year columns not found" unless starts

      current_starts = selected.second
      current_start = current_starts.fetch([ @preferred_current_column, current_starts.length - 1 ].min)
      @current_column = starts.index(current_start)
      @column_year = selected.fourth[current_start, 4]
      starts
    end

    def parse_rows
      rows = {}
      pending = []
      @text.lines.each do |line|
        line = line.chomp
        row_prefix = line[0...[ @column_starts.first - 3, 0 ].max].to_s
        if (match = row_prefix.match(/\A(.*?)\s+(\d{1,2})\s*\z/))
          row = Integer(match[2])
          label = ([ *pending, match[1].strip ].reject(&:blank?).join(" ")).squish
          pending.clear
          raw_text = cell(line, @column_starts.fetch(@current_column))
          rows[row] = { label:, raw_text: raw_text.presence, column_year: @column_year }
        elsif continuation?(line)
          pending << line.strip
        else
          pending.clear
        end
      end
      rows
    end

    def cell(line, start)
      finish = @column_starts[@current_column + 1]
      left = start
      right = finish ? [ finish, line.length ].min : line.length
      segment = line[left...right].to_s
      segment[NUMBER]&.strip
    end

    def continuation?(line)
      stripped = line.strip
      stripped.present? && !stripped.match?(/\A(?:Revenus|Charges|ACTIFS|PASSIFS|Budget|Réalisations|EXCÉDENT|Les notes|Voir les notes)/i) &&
        !stripped.match?(/\d[\d ,.\u00A0\u202F]{2,}/)
    end
  end


  class OcrFormPage
    NUMBER = /\(?-?\d[\d,.]*\)?/

    def initialize(text, fiscal_year, current_column:)
      @lines = text.lines.map(&:strip)
      @fiscal_year = fiscal_year
      header = @lines.max_by { _1.scan(/(?<!\d)(?:19|20)\d{2}(?!\d)/).length }
      years = header.to_s.scan(/(?<!\d)(?:19|20)\d{2}(?!\d)/)
      if years.empty?
        raise Unsupported, "table OCR current-year columns not found for #{@fiscal_year}; header=#{header.inspect}"
      end

      current_indexes = years.each_index.select { years[_1] == fiscal_year.to_s }
      if current_indexes.empty?
        raise Unsupported, "table OCR current year #{@fiscal_year} absent; header=#{header.inspect}"
      end
      @expected_columns = years.length
      @current_column = current_indexes.fetch([ current_column, current_indexes.length - 1 ].min)
    end

    def label(pattern)
      index = @lines.index { _1.match?(pattern) }
      return unless index

      line = @lines[index, 2].find { value(_1) }
      entry(line, @lines[index]) if line
    end

    def section_total(start_pattern, finish_pattern, label:)
      start_index = @lines.index { _1.match?(start_pattern) }
      return unless start_index

      finish_index = @lines.each_index.find { _1 > start_index && @lines[_1].match?(finish_pattern) }
      return unless finish_index

      line = @lines[(start_index + 1)...finish_index].reverse.find { value(_1) }
      entry(line, label) if line
    end

    def section_rows(start_pattern, finish_pattern)
      start_index = @lines.index { _1.match?(start_pattern) }
      return [] unless start_index

      finish_index = @lines.each_index.find { _1 > start_index && @lines[_1].match?(finish_pattern) }
      return [] unless finish_index

      @lines[(start_index + 1)...finish_index].filter_map { row_entry(_1) }
    end

    private

    def entry(line, label)
      { label:, raw_text: value(line), column_year: @fiscal_year.to_s }
    end

    def value(line)
      tokens = line.to_s.scan(NUMBER)
      return if tokens.length < @expected_columns

      tokens.last(@expected_columns).fetch(@current_column)
    end

    def row_entry(line)
      matches = line.to_enum(:scan, NUMBER).map do
        [ Regexp.last_match[0], Regexp.last_match.begin(0) ]
      end
      return if matches.length < @expected_columns

      columns = matches.last(@expected_columns)
      label = line[0...columns.first.second].to_s.sub(/\s+\d{1,2}\s*\z/, "").squish
      return if label.blank? || label.match?(/\A\d+\z/)

      { label:, raw_text: columns.fetch(@current_column).first, column_year: @fiscal_year.to_s }
    end
  end
end
