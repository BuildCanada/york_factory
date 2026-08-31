class Warehouse::FinancialStatementExtraction::FallbackPipeline
  def initialize(primary:, fallback:, on:)
    @primary = primary
    @fallback = fallback
    @on = on
  end

  def run
    @primary.run
  rescue => error
    raise unless error.is_a?(@on)

    Rails.logger.info("Deterministic financial-statement parser fell back: #{error.message}")
    @fallback.run
  end
end
