namespace :financial_facts do
  desc "Extract one persisted financial statement extraction (EXTRACTION_ID, PDF_PATH, INSTITUTION_NAME, optional POPULATION)"
  task extract: :environment do
    extraction_id = ENV.fetch("EXTRACTION_ID")
    pdf_path = ENV.fetch("PDF_PATH")
    institution_name = ENV.fetch("INSTITUTION_NAME")
    population = ENV["POPULATION"]&.to_f
    extraction = Warehouse::FinancialStatementExtraction.find(extraction_id)
    result = extraction.extractor.extract(pdf_path:, institution_name:, population:)
    puts JSON.pretty_generate(status: result.status, facts: result.facts, checks: result.checks)
  end
end
