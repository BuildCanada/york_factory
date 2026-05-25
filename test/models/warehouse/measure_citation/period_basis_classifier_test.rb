require "test_helper"

class Warehouse::MeasureCitation::PeriodBasisClassifierTest < ActiveSupport::TestCase
  setup do
    @jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(code: "PB-#{SecureRandom.hex(2)}") do |j|
      j.name = "PB Test"
      j.slug = "pb-test-#{SecureRandom.hex(2)}"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count" }
    @org = Warehouse::Organization.create!(jurisdiction: @jurisdiction, slug: "pb-org-#{SecureRandom.hex(2)}", canonical_name: "PB Org #{SecureRandom.hex(2)}")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jurisdiction, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/pb-#{SecureRandom.hex(4)}.pdf")
    @measure = Warehouse::Measure.create!(organization: @org, slug: "pb-m-#{SecureRandom.hex(2)}", canonical_name: "Permits", unit: @unit)
  end

  test "interprets a valid LLM response into a Result" do
    citation = build_citation(notes: "YTD as of Sep 30")
    classifier = citation.period_basis_classifier
    parsed = { "id" => citation.id, "period_basis" => "ytd_q3", "confidence" => 0.9, "reasoning" => "explicit Q3" }
    result = classifier.send(:interpret, parsed)
    assert_equal "ytd_q3", result.period_basis
    assert_equal 0.9, result.confidence
  end

  test "rejects unknown period_basis labels" do
    citation = build_citation(notes: "?")
    classifier = citation.period_basis_classifier
    result = classifier.send(:interpret, { "id" => citation.id, "period_basis" => "made_up", "confidence" => 0.95 })
    assert_nil result.period_basis
  end

  test "returns default Result when LLM omits a row" do
    citation = build_citation(notes: "?")
    classifier = citation.period_basis_classifier
    result = classifier.send(:interpret, nil)
    assert_equal "full_year", result.period_basis
    assert_equal 0.0, result.confidence
  end

  test "classify_batch yields one result per citation in order" do
    c1 = build_citation(notes: "YTD as of Mar 31", year: 2024)
    c2 = build_citation(notes: "cumulative annual",  year: 2025, type: "target")

    stubbed_response = [
      { "id" => c1.id, "period_basis" => "ytd_q1", "confidence" => 0.95, "reasoning" => "Q1" },
      { "id" => c2.id, "period_basis" => "full_year", "confidence" => 0.85, "reasoning" => "cumulative=full" }
    ].to_json

    fake_msg = Struct.new(:content).new(stubbed_response)
    fake_chat = Object.new
    fake_chat.define_singleton_method(:ask) { |_p| fake_msg }

    yielded = []
    RubyLLM.singleton_class.alias_method :original_chat, :chat
    RubyLLM.singleton_class.define_method(:chat) { |**_kw| fake_chat }
    begin
      Warehouse::MeasureCitation::PeriodBasisClassifier.classify_batch([ c1, c2 ]) do |citation, result|
        yielded << [ citation.id, result.period_basis, result.confidence ]
      end
    ensure
      RubyLLM.singleton_class.alias_method :chat, :original_chat
      RubyLLM.singleton_class.remove_method :original_chat
    end

    assert_equal [
      [ c1.id, "ytd_q1", 0.95 ],
      [ c2.id, "full_year", 0.85 ]
    ], yielded
  end

  test "strips Markdown fences from LLM responses" do
    citation = build_citation(notes: "?")
    classifier = citation.period_basis_classifier
    raw = "```json\n[{\"id\": #{citation.id}, \"period_basis\": \"as_of_date\", \"confidence\": 0.9}]\n```"
    extracted = classifier.send(:extract_json_array, raw)
    assert_equal [ { "id" => citation.id, "period_basis" => "as_of_date", "confidence" => 0.9 } ], JSON.parse(extracted)
  end

  private

  def build_citation(notes:, year: 2024, type: "actual")
    Warehouse::MeasureCitation.create!(
      measure: @measure, document: @doc, measurement_year: year,
      value_type: type, value_numeric: 100, notes: notes
    )
  end
end
