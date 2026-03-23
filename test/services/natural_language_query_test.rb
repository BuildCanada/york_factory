require "test_helper"

class NaturalLanguageQueryTest < ActiveSupport::TestCase
  test "rejects mutation queries" do
    query = NaturalLanguageQuery.new
    original = LlmClient.instance

    fake = Object.new
    fake.define_singleton_method(:generate_sql) { |**_| { sql: "DELETE FROM organizations", explanation: "test" } }
    LlmClient.instance_variable_set(:@instance, fake)

    result = query.ask("delete everything")
    assert_equal "Query rejected: only SELECT queries are allowed", result[:error]
  ensure
    LlmClient.instance_variable_set(:@instance, original)
  end

  test "rejects DROP queries" do
    query = NaturalLanguageQuery.new
    original = LlmClient.instance

    fake = Object.new
    fake.define_singleton_method(:generate_sql) { |**_| { sql: "DROP TABLE organizations", explanation: "test" } }
    LlmClient.instance_variable_set(:@instance, fake)

    result = query.ask("drop the table")
    assert_equal "Query rejected: only SELECT queries are allowed", result[:error]
  ensure
    LlmClient.instance_variable_set(:@instance, original)
  end

  test "handles LLM errors gracefully" do
    query = NaturalLanguageQuery.new
    original = LlmClient.instance

    fake = Object.new
    fake.define_singleton_method(:generate_sql) { |**_| { sql: nil, explanation: "Error: API timeout" } }
    LlmClient.instance_variable_set(:@instance, fake)

    result = query.ask("what is the budget?")
    assert_equal "Error: API timeout", result[:error]
  ensure
    LlmClient.instance_variable_set(:@instance, original)
  end
end
