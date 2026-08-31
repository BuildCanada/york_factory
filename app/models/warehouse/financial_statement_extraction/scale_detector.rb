class Warehouse::FinancialStatementExtraction::ScaleDetector
  EXPLICIT_UNITS = /(?:\b(?:all (?:amounts|numbers) (?:are )?|amounts? (?:are )?)(?:expressed |reported )?in\s+)?(?:thousands?|millions?)\s+of\s+dollars\b|\(\s*in\s+(?:thousands?|millions?)\s+of\s+dollars\s*\)/i
  MILLIONS = /(?:\b(?:in|en)\s+millions?\b|\(\s*\$?\s*millions?\s*\))/i
  THOUSANDS = /(?:\b(?:in|en)\s+(?:thousands?|milliers?)\b|\(\s*\$?\s*0{3}(?:['’]?s)?\s*\)|\$\s*0{3}(?:['’]?s)?)/i

  def self.detect(page_texts)
    text = Array(page_texts).join("\n")
    if (declaration = text.match(EXPLICIT_UNITS))
      return declaration[0].match?(/million/i) ? 1_000_000 : 1_000
    end
    return 1_000_000 if text.match?(MILLIONS)
    return 1_000 if text.match?(THOUSANDS)

    1
  end
end
