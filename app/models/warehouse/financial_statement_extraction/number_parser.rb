class Warehouse::FinancialStatementExtraction::NumberParser
  class ParseError < StandardError; end

  # Tier 2 evidence for ".": Chapple 2023, asset
  # c4b2b35602f5c5eb7fa7794243eff9366c17326c7203c148556231797a8b2d94, PDF page 7 visibly
  # leaves the current-year Municipal grants cell blank where OCR emits a lone period.
  # Tier 2 evidence for "‒": Frontenac Islands 2011, asset
  # 069e092e31ff06f9fe6649f4259701865581e028d6997f08dea70b547c50a375, PDF page 7 visibly
  # prints figure dashes in empty numeric cells, matching the embedded text layer.
  # Tier 2 evidence for "−": Middlesex 2019, asset
  # a091909bd131307b8b9b2d927cdecd51e2d25099f5ac950aa1fc4e041e381e6d, PDF page 6 visibly
  # prints standalone minus signs in empty numeric cells while negative values use parentheses.
  NULL_MARKERS = [ "", "-", "‐", "‒", "—", "–", "−", "=", ".", '"', "“", "”", "„", "‟", "″", "′′", "nil", "null", "n/a" ].freeze

  def self.null_marker?(raw_text)
    normalized = raw_text.to_s.unicode_normalize(:nfkc).tr("\u00A0\u202F", "  ").strip.downcase
    NULL_MARKERS.include?(normalized) || normalized.match?(/\A[$€£]?\s*[-‐‒—–−=]{1,3}\z/)
  end

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
    text = repair_leading_ocr_quote(text)
    if (match = text.match(/\A\{(?<numeric>[0-9][0-9,.\s]*)\)\z/))
      text = "(#{match[:numeric]})"
    end
    raise ParseError, "blank, dash, and zero are distinct; a fact cannot use a null marker" if self.class.null_marker?(text)
    validate_signs!(text)

    negative = text.match?(/\A\s*[$€£]?\s*\(.*\)\s*\z/) || text.match?(/\A\s*-/) || text.match?(/-\s*\z/)
    numeric = text.gsub(/[()$€£]/, "").gsub(/\b(?:cad|can|dollars?|milliers?|millions?)\b/i, "")
      .gsub(/[+\-]/, "").strip
    numeric = numeric.gsub(/[[:space:]]/, "")
    numeric = repair_ocr_thousands_separator(numeric)
    numeric = repair_trailing_ocr_period(numeric)
    numeric = repair_ocr_digit_glyphs(numeric)
    numeric = normalize_separators(numeric)
    raise ParseError, "not a numeric token: #{@raw_text.inspect}" unless numeric.match?(/\A\d+(?:\.\d+)?\z/)

    value = BigDecimal(numeric)
    value = -value if negative
    value = -value.abs if net_debt_label? && !negative
    value = -value.abs if deficit_label? && !negative
    value
  end

  private

  def validate_signs!(text)
    signs = text.scan(/[+-]/)
    return if signs.empty?

    valid = signs.one? && (text.match?(/\A\s*[$€£]?\s*[+-]/) || text.match?(/[+-]\s*\z/))
    raise ParseError, "not a numeric token: #{@raw_text.inspect}" unless valid
  end

  # OCR repairs must match the full token and still pass downstream accounting
  # and source checks. Tier 1 removes junk without changing a value, tier 2
  # recognizes nulls, and tier 3 substitutes characters only after visual
  # verification of a triggering source.
  def repair_leading_ocr_quote(text)
    return text unless text.match?(/\A['’][[:space:]]+\d{1,3}(?:,\d{3})+\z/)

    text.sub(/\A['’][[:space:]]+/, "")
  end

  def repair_ocr_thousands_separator(numeric)
    if numeric.match?(/\A\d{1,3}(?:,\d{3})*,['’],\d{3}(?:,\d{3})*\z/)
      return numeric.sub(/,['’],/, ",")
    end
    # Tier 1 evidence: Neepawa 2010, asset
    # 4c4f7da9248bb306742b8dc10bc7b0ed00bcd591d0a6a67bbcdaddec1e6c94cf, PDF page 23 visibly
    # prints 20,159 where its embedded text layer contains 20,'159.
    if numeric.match?(/\A\d{1,3}(?:,\d{3})*,['’]\d{3}(?:,\d{3})*\z/)
      return numeric.sub(/,['’]/, ",")
    end

    numeric
  end

  def repair_trailing_ocr_period(numeric)
    return numeric unless numeric.match?(/\A\d{1,3}(?:,\d{3})+\.\z/)

    numeric.delete_suffix(".")
  end

  # Tier 3 evidence: Pelee 2024, asset 74ddb8b64692f591a944b4e02a16aaca748db33b016b049ee5088b35ef176140,
  # PDF page 23 visibly prints 11,744 where its text layer contains ll,744.
  def repair_ocr_digit_glyphs(numeric)
    return numeric unless numeric.match?(/\All(?:,\d{3})+\z/)

    numeric.sub(/\All/, "11")
  end

  def normalize_separators(numeric)
    if numeric.include?(",") && numeric.include?(".")
      return numeric.delete(",.") if numeric.match?(/\A\d{1,3}(?:[,.]\d{3})+\z/)

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
    @concept == "net_financial_assets" &&
      @raw_label.match?(/\b(?:net debt|dette nette)\b/i) &&
      !@raw_label.match?(/\b(?:net financial assets|actifs financiers nets)\b/i)
  end

  def deficit_label?
    @concept.in?(%w[annual_surplus accumulated_surplus opening_accumulated_surplus]) &&
      @raw_label.match?(/\b(?:deficit|déficit)\b/i) &&
      !@raw_label.match?(/\b(?:surplus|exc[eéÉ]dent)\b/i)
  end
end
