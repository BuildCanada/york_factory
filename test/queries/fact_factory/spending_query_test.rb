require "test_helper"

# SpendingQuery against the indexes fact-factory built for it
# (db/fact_factory_api/api_schema.sql, 6b3034e).
class FactFactorySpendingQueryTest < ActiveSupport::TestCase
  test "q searches exactly the expression fact-factory indexes" do
    schema = File.read(FactFactoryApiDatabase::SCHEMA)
    indexed = schema[/api_spending_records_text ON api\.spending_records USING gin \(to_tsvector\('simple',(.*?)\)\);/m, 1]
    assert indexed, "the full-text index is in the vendored schema"
    squish = ->(sql) { sql.gsub(/\s+/, " ").strip }
    assert_equal squish.(indexed), squish.(FactFactory::SpendingQuery::TEXT.gsub("r.", ""))
  end

  # fact-factory's planner tests cover the other indexes at size
  # (tests/test_api_indexes.py); on these few rows only the GIN index is
  # chosen reliably.
  test "the planner uses the full-text index for q" do
    FactFactoryRecord.connection.transaction do
      FactFactoryRecord.connection.execute("SET LOCAL enable_seqscan = off")
      text = plan("SELECT 1 FROM api.spending_records r WHERE to_tsvector('simple', #{FactFactory::SpendingQuery::TEXT}) @@ plainto_tsquery('simple', 'rink')")
      assert_includes text, "api_spending_records_text"
    end
  end

  private

  def plan(sql) = FactFactoryRecord.connection.select_values("EXPLAIN #{sql}").join("\n")
end
