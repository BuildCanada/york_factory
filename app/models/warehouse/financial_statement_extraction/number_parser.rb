class Warehouse::FinancialStatementExtraction::NumberParser
  class ParseError < StandardError; end

  NULL_MARKERS = [ "", "-", "—", "–", "nil", "null", "n/a" ].freeze

  def self.parse(raw_text, raw_label: nil, concept: nil)
    new(raw_text, raw_label:, concept:).parse
  end

  def initialize(raw_text, raw_label: nil, concept: nil)
    @raw_text = raw_text.to_s
    @raw_label = raw_label.to_s
    @concept = concept.to_s
  end

  def parse
    text = @raw_text.unicode_normalize(:nfkc).tr("\u00A0\u202F", "  ").strip
    raise ParseError, "blank, dash, and zero are distinct; a fact cannot use a null marker" if NULL_MARKERS.include?(text.downcase)

    negative = text.match?(/\A\s*\(.*\)\s*\z/) || text.match?(/\A\s*-/) || text.match?(/-\s*\z/)
    numeric = text.gsub(/[()$€£]/, "").gsub(/\b(?:cad|can|dollars?|milliers?|millions?)\b/i, "")
      .gsub(/[+\-]/, "").strip
    numeric = numeric.gsub(/[[:space:]]/, "")
    numeric = normalize_separators(numeric)
    raise ParseError, "not a numeric token: #{@raw_text.inspect}" unless numeric.match?(/\A\d+(?:\.\d+)?\z/)

    value = BigDecimal(numeric)
    value = -value if negative
    value = -value.abs if net_debt_label? && !negative
    value = -value.abs if deficit_label? && !negative
    value
  end

  private

  def normalize_separators(numeric)
    if numeric.include?(",") && numeric.include?(".")
      decimal_separator = numeric.rindex(",") > numeric.rindex(".") ? "," : "."
      thousands_separator = decimal_separator == "," ? "." : ","
      numeric.delete(thousands_separator).sub(decimal_separator, ".")
    elsif numeric.count(",") > 1 || numeric.match?(/\A\d{1,3}(?:,\d{3})+\z/)
      numeric.delete(",")
    elsif numeric.count(".") > 1 || numeric.match?(/\A\d{1,3}(?:\.\d{3})+\z/)
      numeric.delete(".")
    elsif numeric.match?(/,\d{1,2}\z/)
      numeric.sub(",", ".")
    else
      numeric.delete(",")
    end
  end

  def net_debt_label?
    @concept == "net_financial_assets" && @raw_label.match?(/\b(?:net debt|dette nette)\b/i)
  end

  def deficit_label?
    @concept.in?(%w[annual_surplus accumulated_surplus opening_accumulated_surplus]) &&
      @raw_label.match?(/\b(?:deficit|déficit)\b/i)
  end
end
