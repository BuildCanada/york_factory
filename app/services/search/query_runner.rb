module Search
  class QueryRunner
    Result = Data.define(:rows, :billing, :performance, :query_count)
    ProviderResult = Data.define(:rows, :billing, :performance)

    INCLUDE_ATTRIBUTES = %w[
      realm record_type search_revision search_content_hash index_sequence title summary
      canonical_url source_name source_domain published_at language publisher_name
      publisher_domain content_type authors section word_count amount currency award_type
      payer_names recipient_name program_name fiscal_year occurred_at dataset_key
      kpi_measure_name kpi_measure_slug kpi_measure_description kpi_category
      kpi_service_category kpi_aggregation_type kpi_frequency kpi_unit_symbol
      kpi_last_updated_at
    ].freeze

    def initialize(namespace: Search.turbopuffer_namespace,
      embedding_client: Search::Embedding::AzureCohereClient.new)
      @namespace = namespace
      @embedding_client = embedding_client
    end

    def call(definition, realm: nil, from_sequence: nil, to_sequence: nil, limit: 100, evaluated_at: Time.current)
      compiler = Search::QueryCompiler.new(definition, realm:, evaluated_at:)
      case compiler.mode
      when "filter_only"
        result(query(
          rank_by: [ "index_sequence", "asc" ],
          filters: compiler.filters(from_sequence:, to_sequence:),
          limit:,
          include_attributes: INCLUDE_ATTRIBUTES
        ))
      when "lexical"
        result(lexical(compiler, from_sequence:, to_sequence:, limit:))
      when "semantic"
        semantic_result(compiler, from_sequence:, to_sequence:, limit:)
      when "hybrid"
        hybrid_result(compiler, from_sequence:, to_sequence:, limit:)
      end
    end

    private

    def lexical(compiler, from_sequence:, to_sequence:, limit:)
      query(
        rank_by: [ compiler.lexical_field, "BM25", compiler.text ],
        filters: compiler.filters(from_sequence:, to_sequence:, lexical_membership: true),
        limit:,
        include_attributes: INCLUDE_ATTRIBUTES
      )
    end

    def semantic(compiler, from_sequence:, to_sequence:, limit:)
      vector = @embedding_client.embed_queries([ compiler.text ]).vectors.fetch(0)
      query(
        rank_by: [ "embedding", "ANN", vector ],
        filters: compiler.filters(from_sequence:, to_sequence:),
        limit:,
        include_attributes: INCLUDE_ATTRIBUTES
      )
    end

    def query(**parameters)
      response = deep_hash(@namespace.query(**parameters, consistency: { level: :strong }))
      ProviderResult.new(
        rows: Array(response[:rows] || response["rows"]).map { |row| deep_hash(row) },
        billing: deep_hash(response[:billing] || response["billing"] || {}),
        performance: deep_hash(response[:performance] || response["performance"] || {})
      )
    end

    def semantic_result(compiler, from_sequence:, to_sequence:, limit:)
      provider = semantic(compiler, from_sequence:, to_sequence:, limit:)
      rows = provider.rows.select { |row| distance(row) <= compiler.semantic_max_distance }
      result(provider, rows:)
    end

    def hybrid_result(compiler, from_sequence:, to_sequence:, limit:)
      lexical_result = lexical(compiler, from_sequence:, to_sequence:, limit:)
      semantic_result = semantic(compiler, from_sequence:, to_sequence:, limit:)
      semantic_rows = semantic_result.rows.select { |row| distance(row) <= compiler.semantic_max_distance }
      rows = rrf(lexical_result.rows, semantic_rows).first(limit)

      Result.new(
        rows:,
        billing: merge_metrics(lexical_result.billing, semantic_result.billing),
        performance: merge_metrics(lexical_result.performance, semantic_result.performance),
        query_count: 2
      )
    end

    def result(provider, rows: provider.rows)
      Result.new(rows:, billing: provider.billing, performance: provider.performance, query_count: 1)
    end

    def distance(row)
      value = row[:"$dist"] || row["$dist"]
      value.nil? ? Float::INFINITY : value.to_f
    end

    def rrf(*rankings)
      scores = Hash.new(0.0)
      rows_by_id = {}
      rankings.each do |rows|
        rows.each_with_index do |row, index|
          id = row[:id] || row["id"]
          rows_by_id[id] ||= row
          scores[id] += 1.0 / (61 + index)
        end
      end
      rows_by_id.values.sort_by { |row| -scores.fetch(row[:id] || row["id"]) }
    end

    def merge_metrics(*metrics)
      metrics.compact.reduce({}) do |merged, metric|
        merged.merge(metric) do |_key, left, right|
          left.is_a?(Numeric) && right.is_a?(Numeric) ? left + right : right
        end
      end
    end

    def deep_hash(value)
      return value.map { |child| deep_hash(child) } if value.is_a?(Array)
      return value.transform_values { |child| deep_hash(child) } if value.is_a?(Hash)
      return deep_hash(value.deep_to_h) if value.respond_to?(:deep_to_h)
      return deep_hash(value.to_h) if value.respond_to?(:to_h)

      value
    end
  end
end
