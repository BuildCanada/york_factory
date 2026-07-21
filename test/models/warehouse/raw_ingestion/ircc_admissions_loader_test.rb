require "test_helper"

class Warehouse::RawIngestion::IrccAdmissionsLoaderTest < ActiveSupport::TestCase
  HEADER = [
    "EN_YEAR", "EN_QUARTER", "EN_MONTH", "FR_ANNEÉ", "FR_TRIMESTRE", "FR_MOIS",
    "EN_PROVINCE_TERRITORY", "FR_PROVINCE_TERRITOIRE",
    "EN_IMMIGRATION_CATEGORY-MAIN_CATEGORY", "FR_CATÉGORIE_D'IMMIGRATION-CATÉGORIE_PRINCIPALE",
    "EN_IMMIGRATION_CATEGORY-GROUP", "FR_CATÉGORIE_D'IMMIGRATION-GROUPE",
    "EN_IMMIGRATION_CATEGORY-COMPONENT", "FR_CATÉGORIE_D'IMMIGRATION-COMPOSANTE",
    "TOTAL"
  ].freeze

  setup do
    suffix = SecureRandom.hex(4)

    unit = Warehouse::Unit.find_or_create_by!(symbol: "count") do |u|
      u.kind = "absolute"
      u.base_unit = "count"
    end
    @measures = {}
    {
      "pr-admissions-total" => "Permanent resident admissions, all categories (Canada, persons)",
      "pr-admissions-economic" => "Permanent resident admissions, economic (Canada, persons)",
      "pr-admissions-family" => "Permanent resident admissions, sponsored family (Canada, persons)"
    }.each do |slug, name|
      @measures[slug] = Warehouse::Measure.find_or_create_by!(organization_id: nil, slug: slug) do |m|
        m.canonical_name = name
        m.unit = unit
        m.aggregation_type = "non_aggregable"
        m.frequency = "monthly"
      end
    end

    [ [ "G7", "G7 (average)", "supranational" ], [ "INTL", "International", "supranational" ] ].each do |code, name, level|
      Warehouse::Jurisdiction.find_or_create_by!(code: code) do |j|
        j.name = name
        j.slug = code.downcase
        j.level = level
        j.fiscal_year_start_month = 1
        j.default_currency = "USD"
      end
    end

    source = Warehouse::Source.create!(
      name: "econ_ircc_test_#{suffix}",
      url: "https://www.ircc.canada.ca/opendata-donneesouvertes/data/ODP-PR-PT_IMMCAT.csv",
      format: "csv"
    )
    @raw_ingestion = source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/#{suffix}.csv",
      checksum: SecureRandom.hex(32),
      status: :pending
    )
  end

  # The leading string literal is a U+FEFF byte-order mark, matching the
  # real IRCC file.
  def tsv(*rows)
    "﻿" + ([ HEADER ] + rows).map { |r| r.join("\t") }.join("\r\n") + "\r\n"
  end

  def row(year:, month:, province:, category:, total:, group: "Worker Program", component: "Skilled Worker")
    [ year, "Q1", month, year, "T1", "fév.", province, province,
      category, category, group, group, component, component, total ]
  end

  test "sums provinces and components into Canada-wide monthly category totals" do
    body = tsv(
      row(year: "2025", month: "Feb", province: "Alberta", category: "Economic", total: "545"),
      row(year: "2025", month: "Feb", province: "Ontario", category: "Economic", total: "2300"),
      row(year: "2025", month: "Feb", province: "Ontario", category: "Economic", total: "150",
          group: "Provincial Nominee Program", component: "Provincial Nominee Program"),
      row(year: "2025", month: "Feb", province: "Ontario", category: "Sponsored Family", total: "800"),
      row(year: "2025", month: "Mar", province: "Ontario", category: "Economic", total: "1000")
    )

    counts = @raw_ingestion.ircc_admissions_loader.load(csv_content: body)

    assert_equal "complete", @raw_ingestion.reload.status
    assert counts[:inserted] >= 5

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    feb = Date.new(2025, 2, 1)

    economic = Warehouse::CanonicalObservation.find_by!(
      measure_id: @measures["pr-admissions-economic"].id, jurisdiction_id: canada.id, period_start: feb
    )
    assert_equal 2995.0, economic.value_numeric
    assert_equal "month", economic.period_basis

    family = Warehouse::CanonicalObservation.find_by!(
      measure_id: @measures["pr-admissions-family"].id, jurisdiction_id: canada.id, period_start: feb
    )
    assert_equal 800.0, family.value_numeric

    total = Warehouse::CanonicalObservation.find_by!(
      measure_id: @measures["pr-admissions-total"].id, jurisdiction_id: canada.id, period_start: feb
    )
    assert_equal 3795.0, total.value_numeric

    march_total = Warehouse::CanonicalObservation.find_by!(
      measure_id: @measures["pr-admissions-total"].id, jurisdiction_id: canada.id, period_start: Date.new(2025, 3, 1)
    )
    assert_equal 1000.0, march_total.value_numeric
  end

  test "treats suppressed values as zero and skips non-numeric artifacts" do
    body = tsv(
      row(year: "2025", month: "Feb", province: "Alberta", category: "Economic", total: "--"),
      row(year: "2025", month: "Feb", province: "Alberta", category: "Economic", total: "G"),
      row(year: "2025", month: "Feb", province: "Alberta", category: "Economic", total: "40")
    )

    @raw_ingestion.ircc_admissions_loader.load(csv_content: body)

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    economic = Warehouse::CanonicalObservation.find_by!(
      measure_id: @measures["pr-admissions-economic"].id, jurisdiction_id: canada.id,
      period_start: Date.new(2025, 2, 1)
    )
    assert_equal 40.0, economic.value_numeric
  end

  test "counts unmapped categories in the total only" do
    body = tsv(
      row(year: "2025", month: "Feb", province: "Alberta", category: "Economic", total: "100"),
      row(year: "2025", month: "Feb", province: "Alberta", category: "Brand New Category", total: "60")
    )

    @raw_ingestion.ircc_admissions_loader.load(csv_content: body)

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    total = Warehouse::CanonicalObservation.find_by!(
      measure_id: @measures["pr-admissions-total"].id, jurisdiction_id: canada.id,
      period_start: Date.new(2025, 2, 1)
    )
    assert_equal 160.0, total.value_numeric

    economic = Warehouse::CanonicalObservation.find_by!(
      measure_id: @measures["pr-admissions-economic"].id, jurisdiction_id: canada.id,
      period_start: Date.new(2025, 2, 1)
    )
    assert_equal 100.0, economic.value_numeric
  end

  test "marks the ingestion failed and re-raises on malformed payloads" do
    assert_raises(CSV::MalformedCSVError) do
      @raw_ingestion.ircc_admissions_loader.load(csv_content: "a\tb\n\"unclosed\t1\n")
    end

    assert_equal "failed", @raw_ingestion.reload.status
    assert @raw_ingestion.error_message.present?
  end
end
