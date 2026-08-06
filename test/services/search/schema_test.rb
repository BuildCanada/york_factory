require "test_helper"

class Search::SchemaTest < ActiveSupport::TestCase
  test "builds one compatible union schema for every realm" do
    schema = Search::Schema.document

    assert_equal "[1024]f16", schema.dig(:embedding, :type)
    assert_equal "string", schema.dig(:realm, :type)
    assert schema.key?(:amount)
    assert schema.key?(:publisher_domain)
    assert schema.key?(:kpi_measure_id)
    assert schema.key?(:kpi_last_updated_at)
    refute schema.key?(:kpi_value_numeric)
    refute schema.key?(:kpi_value_text)
    assert_match(/\A[0-9a-f]{64}\z/, Search::Schema.digest)
  end
end
