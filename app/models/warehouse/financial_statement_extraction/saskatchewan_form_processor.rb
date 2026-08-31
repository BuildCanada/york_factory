class Warehouse::FinancialStatementExtraction::SaskatchewanFormProcessor < Warehouse::FinancialStatementExtraction::QuebecFormProcessor
  private

  def pipeline_class = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline
end
