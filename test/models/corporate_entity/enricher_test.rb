require "test_helper"
require "ostruct"

class CorporateEntity::EnricherTest < ActiveSupport::TestCase
  setup do
    @corp = CorporateEntity.create!(
      jurisdiction: "federal",
      registry_id: "99999",
      legal_name: "Test Federal Corp",
      source_system: "ised_xml"
    )
  end

  test "creates directors from API response" do
    api_response = {
      "directors" => [
        {
          "name" => "Jane Smith",
          "address" => "123 Main St",
          "province" => "ON",
          "postalCode" => "K1A 0A1",
          "country" => "Canada",
          "residentCanadian" => true,
          "appointmentDate" => "2020-01-15",
          "role" => "Director"
        }
      ]
    }

    enricher = @corp.enricher
    enricher.define_singleton_method(:fetch_directors) { api_response }

    enricher.enrich

    assert @corp.reload.enriched?
    assert_not_nil @corp.enriched_at
    assert_equal 1, CorporateDirector.count
    assert_equal 1, DirectorAppointment.count

    director = CorporateDirector.first
    assert_equal "Jane Smith", director.full_name
    assert_equal "jane smith", director.normalized_name
    assert_equal "ON", director.province

    appt = DirectorAppointment.first
    assert_equal @corp, appt.corporate_entity
    assert_equal Date.new(2020, 1, 15), appt.appointed_date
    assert_equal "Director", appt.role
  end

  test "skips non-federal entities" do
    bc_corp = CorporateEntity.create!(
      jurisdiction: "bc", registry_id: "BC123", legal_name: "BC Corp"
    )

    bc_corp.enricher.enrich

    assert_not bc_corp.reload.enriched?
    assert_equal 0, CorporateDirector.count
  end

  test "skips already enriched entities" do
    @corp.update!(enriched: true, enriched_at: 1.day.ago)

    @corp.enricher.enrich

    assert_equal 0, CorporateDirector.count
  end

  test "marks needs_review on API error" do
    enricher = @corp.enricher
    enricher.define_singleton_method(:fetch_directors) { raise StandardError, "Connection refused" }

    enricher.enrich

    assert @corp.reload.needs_review?
    assert_not @corp.enriched?
  end

  test "handles empty director list" do
    enricher = @corp.enricher
    enricher.define_singleton_method(:fetch_directors) { { "directors" => [] } }

    enricher.enrich

    assert @corp.reload.enriched?
    assert_equal 0, CorporateDirector.count
  end

  test "handles nil API response" do
    enricher = @corp.enricher
    enricher.define_singleton_method(:fetch_directors) { nil }

    enricher.enrich

    assert_not @corp.reload.enriched?
    assert_equal 0, CorporateDirector.count
  end
end
