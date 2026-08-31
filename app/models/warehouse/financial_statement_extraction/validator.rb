class Warehouse::FinancialStatementExtraction::Validator
  REQUIRED_CONCEPTS = %w[
    total_financial_assets total_liabilities net_financial_assets
    total_non_financial_assets accumulated_surplus
    total_revenue total_expenses annual_surplus
  ].freeze
  HARD_CHECK_PREFIXES = %w[required_concepts evidence raw_parse column_year exception_evidence position_ operations_ surplus_rollforward].freeze

  attr_reader :facts, :fiscal_year, :population, :page_texts, :flags

  def initialize(facts:, fiscal_year:, population: nil, page_texts: {}, flags: {})
    @facts = facts
    @fiscal_year = Integer(fiscal_year)
    @population = population&.to_f
    @page_texts = page_texts
    @flags = flags
  end

  def validate
    checks = []
    checks << required_concepts_check
    facts.each do |fact|
      checks << evidence_check(fact)
      checks << raw_parse_check(fact)
      checks << column_year_check(fact)
    end
    checks.concat(exception_evidence_checks)
    checks << identity_check("position_net", %w[total_financial_assets total_liabilities net_financial_assets]) do |financial_assets, liabilities, net_financial_assets|
      financial_assets - liabilities - net_financial_assets
    end
    checks << identity_check("position_surplus", %w[net_financial_assets total_non_financial_assets accumulated_surplus]) do |net_financial_assets, non_financial_assets, accumulated_surplus|
      net_financial_assets + non_financial_assets - accumulated_surplus
    end
    checks << identity_check("operations_surplus", %w[total_revenue total_expenses annual_surplus]) do |revenue, expenses, annual_surplus|
      revenue - expenses - annual_surplus
    end
    checks << rollforward_check
    checks << revenue_per_capita_check
    checks << confidence_check
    checks.compact
  end

  def acceptable?(checks = validate)
    checks.none? { |check| hard_check?(check) && check[:status] == "fail" } &&
      checks.none? { |check| check[:id] == "confidence" && check[:status] == "fail" }
  end

  private

  def required_concepts_check
    missing = REQUIRED_CONCEPTS - by_concept.keys
    check("required_concepts", missing.empty? ? "pass" : "fail",
      missing.empty? ? "all eight required headline concepts are present" : "missing: #{missing.join(', ')}")
  end

  def evidence_check(fact)
    text = page_texts[Integer(fact.fetch(:source_page))].to_s
    label_found = normalized(text).include?(normalized(fact.fetch(:raw_label)))
    number_found = normalized_number(text).include?(normalized_number(fact.fetch(:raw_text)))
    status = label_found && number_found ? "pass" : "fail"
    check("evidence:#{fact.fetch(:concept)}", status,
      "page #{fact.fetch(:source_page)} label=#{label_found} number=#{number_found}")
  end

  def raw_parse_check(fact)
    parsed = Warehouse::FinancialStatementExtraction::NumberParser.parse(
      fact.fetch(:raw_text), raw_label: fact.fetch(:raw_label), concept: fact.fetch(:concept)
    )
    reparsed = parsed * Integer(fact.fetch(:scale))
    expected = decimal(fact.fetch(:value))
    status = reparsed == expected ? "pass" : "fail"
    check("raw_parse:#{fact.fetch(:concept)}", status,
      "raw #{fact.fetch(:raw_text).inspect} × #{fact.fetch(:scale)} = #{reparsed.to_s('F')}; stored #{expected.to_s('F')}")
  rescue Warehouse::FinancialStatementExtraction::NumberParser::ParseError, ArgumentError => error
    check("raw_parse:#{fact.fetch(:concept)}", "fail", error.message)
  end

  def column_year_check(fact)
    label = fact.fetch(:column_year).to_s
    status = label.match?(/(?<!\d)#{Regexp.escape(fiscal_year.to_s)}(?!\d)/) && !label.match?(/budget|budgétaire|comparative?/i) ? "pass" : "fail"
    check("column_year:#{fact.fetch(:concept)}", status,
      "expected current-year actual #{fiscal_year}; received #{label.inspect}")
  end

  def identity_check(id, concepts)
    return check(id, "skip", "source separately presents accumulated remeasurement gains or losses") if id == "position_surplus" && flags[:remeasurement_present]
    return check(id, "skip", "source separately presents other contributions, transfers, gains, or losses") if id == "operations_surplus" && flags[:operations_adjustment_present]

    selected = concepts.map { |concept| by_concept[concept] }
    return check(id, "skip", "missing: #{concepts.zip(selected).select { |_, fact| fact.nil? }.map(&:first).join(', ')}") if selected.any?(&:nil?)

    discrepancy = yield(*selected.map { |fact| decimal(fact.fetch(:value)) })
    tolerance = selected.map { |fact| Integer(fact.fetch(:scale)) }.max
    status = discrepancy.abs <= tolerance ? "pass" : "fail"
    detail = "discrepancy=#{discrepancy.to_s('F')}; tolerance=#{tolerance}"
    detail += "; likely=#{discrepancy_fingerprint(discrepancy)}" if status == "fail"
    check(id, status, detail)
  end

  def rollforward_check
    concepts = %w[opening_accumulated_surplus annual_surplus accumulated_surplus]
    selected = concepts.map { |concept| by_concept[concept] }
    return check("surplus_rollforward", "skip", "opening accumulated surplus was not printed") if selected.first.nil?
    return check("surplus_rollforward", "skip", "missing annual or closing surplus") if selected.drop(1).any?(&:nil?)

    discrepancy = decimal(selected[0].fetch(:value)) + decimal(selected[1].fetch(:value)) - decimal(selected[2].fetch(:value))
    tolerance = selected.map { |fact| Integer(fact.fetch(:scale)) }.max
    return check("surplus_rollforward", "pass", "discrepancy=#{discrepancy.to_s('F')}; tolerance=#{tolerance}") if discrepancy.abs <= tolerance
    return check("surplus_rollforward", "skip", "source indicates a printed restatement, remeasurement, or adjustment; discrepancy=#{discrepancy.to_s('F')}") if flags[:rollforward_adjustment_present]

    check("surplus_rollforward", discrepancy.abs <= tolerance ? "pass" : "fail",
      "discrepancy=#{discrepancy.to_s('F')}; tolerance=#{tolerance}")
  end

  def exception_evidence_checks
    [
      exception_evidence_check(:remeasurement_present, /remeasurement|remesurement|réévaluation|reevaluation/i),
      exception_evidence_check(:operations_adjustment_present, /other contributions|capital contributions|transfers related to capital|gain|loss|autres contributions|transferts?.*immobil|gains?|pertes?/i),
      exception_evidence_check(:rollforward_adjustment_present, /remeasurement|remesurement|restat|retrait|adjust|redress|other comprehensive income|autres? éléments? du résultat global|réévaluation|reevaluation/i)
    ]
  end

  def exception_evidence_check(flag, pattern)
    return check("exception_evidence:#{flag}", "pass", "inactive") unless flags[flag]

    found = relevant_page_text.match?(pattern)
    check("exception_evidence:#{flag}", found ? "pass" : "fail",
      found ? "supporting wording found on a cited page" : "flag lacks supporting wording on cited pages")
  end

  def relevant_page_text
    @relevant_page_text ||= facts.map { |fact| page_texts[Integer(fact.fetch(:source_page))].to_s }.uniq.join("\n")
  end

  def revenue_per_capita_check
    return check("revenue_per_capita", "skip", "population unavailable") unless population&.positive?
    revenue = by_concept["total_revenue"]
    return check("revenue_per_capita", "skip", "revenue unavailable") unless revenue

    per_capita = decimal(revenue.fetch(:value)) / population
    status = per_capita.between?(500, 20_000) ? "pass" : "fail"
    check("revenue_per_capita", status, format("CAD %.2f per resident", per_capita))
  end

  def confidence_check
    confidence = facts.map { |fact| fact.fetch(:extraction_confidence).to_f }.min
    check("confidence", confidence && confidence >= 0.8 ? "pass" : "fail",
      confidence ? format("minimum fact confidence %.3f", confidence) : "no facts")
  end

  def discrepancy_fingerprint(discrepancy)
    value = discrepancy.abs.to_i
    return "none" if value.zero?
    return "doubling" if value.even? && value.to_s.chars.uniq.length <= 2
    return "transposition" if (value % 9).zero?
    return "single_digit" if value.to_s.count("0") >= value.to_s.length - 1

    "unclassified"
  end

  def hard_check?(check)
    HARD_CHECK_PREFIXES.any? { |prefix| check[:id].start_with?(prefix) }
  end

  def by_concept
    @by_concept ||= facts.index_by { |fact| fact.fetch(:concept) }
  end

  def decimal(value)
    value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
  end

  def normalized(value)
    value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.gsub(/[^[:alnum:]]+/, " ").strip
  end

  def normalized_number(value)
    value.to_s.unicode_normalize(:nfkc).tr("\u00A0\u202F", "  ").gsub(/[[:space:],.]/, "").gsub(/[^0-9()\-]/, "")
  end

  def check(id, status, detail)
    { id:, status:, detail: }
  end
end
