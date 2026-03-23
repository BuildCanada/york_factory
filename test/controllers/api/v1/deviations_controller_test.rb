require "test_helper"

class Api::V1::DeviationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Ensure the VIEW exists (VIEWs aren't in schema.rb)
    ActiveRecord::Base.connection.execute(<<~SQL)
      CREATE OR REPLACE VIEW spending_deviations AS
      SELECT
        fa.government_entity_id,
        fa.fiscal_year,
        fa.vote_number,
        fa.vote_type,
        SUM(fa.amount) AS consolidated_estimate,
        COALESCE(MAX(fe.actual_expenditure), 0) AS actual_expenditure,
        COALESCE(MAX(fe.actual_expenditure), 0) - SUM(fa.amount) AS variance_amount,
        CASE WHEN SUM(fa.amount) = 0 THEN 0
             ELSE ROUND(((COALESCE(MAX(fe.actual_expenditure), 0) - SUM(fa.amount)) / SUM(fa.amount) * 100), 2)
        END AS variance_pct
      FROM fiscal_authorities fa
      LEFT JOIN fiscal_expenditures fe
        ON fa.government_entity_id = fe.government_entity_id
        AND fa.fiscal_year = fe.fiscal_year
        AND fa.vote_number = fe.vote_number
      GROUP BY fa.government_entity_id, fa.fiscal_year, fa.vote_number, fa.vote_type,
               fe.actual_expenditure
    SQL

    @entity = GovernmentEntity.create!(canonical_name: "Test Entity")
    FiscalAuthority.create!(
      government_entity: @entity, fiscal_year: "2023-24",
      document_type: "main", vote_number: 1,
      vote_type: "operating", description: "Test", amount: 1_000_000
    )
    FiscalExpenditure.create!(
      government_entity: @entity, fiscal_year: "2023-24",
      vote_number: 1, vote_type: "operating",
      description: "Test", pa_voted_ceiling: 1_000_000,
      actual_expenditure: 1_500_000
    )
  end

  test "index returns deviations with government_entity name" do
    get api_v1_deviations_url
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
    assert_equal "Test Entity", data.first["organization"]
  end

  test "index filters by fiscal_year" do
    get api_v1_deviations_url, params: { fiscal_year: "2023-24" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.size
  end

  test "index filters anomalous deviations" do
    get api_v1_deviations_url, params: { anomalous: "true" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal 1, data.size
  end
end
