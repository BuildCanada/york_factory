module Warehouse::Spending::TypesenseResponse
  module_function

  def render(parameters)
    parameters = parameters.to_h.stringify_keys
    validate_collection!(parameters["collection"])
    result = Warehouse::Spending::Search.new(parameters).call

    {
      found: result.found,
      out_of: result.found,
      page: result.page,
      request_params: {
        collection_name: "records",
        q: result.query.presence || "*",
        per_page: result.per_page
      },
      search_time_ms: result.elapsed_ms,
      hits: result.records.map { |award| hit(award) },
      facet_counts: result.facets.map do |field_name, counts|
        { field_name:, counts:, sampled: false, stats: {} }
      end
    }
  end

  def hit(award)
    {
      document: Warehouse::Spending::Serializer.search_document(award),
      highlight: {},
      highlights: [],
      text_match: 0,
      text_match_info: { best_field_score: "0", best_field_weight: 0, fields_matched: 0, score: "0" }
    }
  end

  def validate_collection!(collection)
    return if collection.blank? || collection == "records"

    raise Warehouse::Spending::Search::InvalidRequest, "unknown collection #{collection.inspect}"
  end
end
