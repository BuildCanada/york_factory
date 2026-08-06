require "test_helper"

class Search::QueryCompilerTest < ActiveSupport::TestCase
  test "adds immutable realm visibility sequence and lexical membership filters" do
    compiler = Search::QueryCompiler.new({
      version: 1,
      realm: "media",
      language: "en",
      text: "housing policy",
      mode: "lexical",
      lexical_match: "phrase",
      filters: { all: [ { field: "publisher_domain", op: "in", value: [ "cbc.ca" ] } ] }
    })

    filters = compiler.filters(from_sequence: 10, to_sequence: 20, lexical_membership: true)

    assert_includes filters.last, [ "realm", "Eq", "media" ]
    assert_includes filters.last, [ "visibility", "Eq", "public" ]
    assert_includes filters.last, [ "index_sequence", "Gt", 10 ]
    assert_includes filters.last, [ "index_sequence", "Lte", 20 ]
    assert_includes filters.last, [ "content_en", "ContainsTokenSequence", "housing policy" ]
  end

  test "expands contains_all into indexed contains predicates" do
    compiler = Search::QueryCompiler.new({
      version: 1,
      realm: "media",
      mode: "filter_only",
      filters: { field: "authors", op: "contains_all", value: [ "A", "B" ] }
    })

    assert_includes compiler.filters.last, [
      "And", [ [ "authors", "Contains", "A" ], [ "authors", "Contains", "B" ] ]
    ]
  end
end
