module PublicApi
  module V1
    # Dataset and DictionaryTerm.
    module CatalogSerializer
      SPENDING_TERMS = %w[amount canonical_id currency external_id fiscal_year is_aggregated payer payer_code recipient
                          record_type revision_rank_json source_key spending_key].freeze
      REGISTRY_TERMS = {
        "entities" => %w[entity_id entity_class subtype name name_fr aliases anchor jurisdiction status valid_from valid_to attributes redirected_to],
        "identifiers" => %w[entity_id namespace value verified vintage valid_from valid_to],
        "relationships" => %w[row_id subject_id predicate object_id object_ref attributes valid_from valid_to],
        "spending_parties" => %w[occurrence_id field position raw_name normalized_name party_kind entity_id method reason candidates]
      }.freeze

      module_function

      # Every dataset the API describes, in asset-key order: the spending
      # sources and the registry tables.
      def datasets(ctx)
        query = FactFactory::DatasetQuery.new(release: ctx.release)
        spending = Catalog.sources.values.map { |s| spending_dataset(s, ctx, query) }
        registry = Catalog.registry_datasets.values.map { |d| registry_dataset(d, ctx, query) }
        (spending + registry).sort_by { |d| d[:asset_key] }
      end

      def spending_dataset(source, ctx, query)
        from, to = query.fiscal_years(source.asset)
        terms = (SPENDING_TERMS + Catalog.asset_notes(source.asset).keys).uniq.select { |t| Catalog.definition(t) }.sort
        {
          asset_key: source.asset, title: source.title, record_meaning: source.record_meaning, publisher: source.publisher,
          license: source.license,
          freshness: { latest_retrieved_at: nil, cadence: source.cadence },
          coverage: {
            rows: query.spending_rows(source.asset),
            from_fiscal_year: Format.fiscal_year(from), to_fiscal_year: Format.fiscal_year(to),
            known_gaps: source.known_gaps
          },
          dictionary_terms: terms,
          caveats: source.caveats.map { |code| Catalog.caveat(code, locale: ctx.locale) },
          bulk: [],
          links: {
            self: ctx.pin("/v1/datasets/#{ERB::Util.url_encode(source.asset)}"),
            records: Links.url("/v1/spending", { "source" => source.key, "as_of" => ctx.release })
          }
        }
      end

      def registry_dataset(d, ctx, query)
        {
          asset_key: d.asset, title: d.title, record_meaning: d.record_meaning, publisher: d.publisher, license: d.license,
          freshness: { latest_retrieved_at: nil, cadence: d.cadence },
          coverage: { rows: FactFactory::ReleaseQuery.counts(ctx.release)[d.table], from_fiscal_year: nil, to_fiscal_year: nil, known_gaps: [] },
          dictionary_terms: REGISTRY_TERMS.fetch(d.table, []).select { |t| Catalog.definition(t) },
          caveats: [],
          bulk: query.exports(table: FactFactory::DatasetQuery::EXPORT_TABLES[d.table]).map { |e| ReleaseSerializer.export(e, query) },
          links: { self: ctx.pin("/v1/datasets/#{ERB::Util.url_encode(d.asset)}"), records: d.records && ctx.pin(d.records) }
        }
      end

      def term(name, definition, notes: false)
        values = case definition["values"]
        when Hash then definition["values"].map { |value, meaning| { value: scalar(value), meaning: meaning&.to_s } }
        when Array then definition["values"].map { |value| { value: scalar(value), meaning: nil } }
        else []
        end
        data = {
          term: name, meaning: definition["meaning"].to_s, type: definition["type"]&.to_s, units: definition["units"]&.to_s,
          values:, blank_means: definition["blank_means"]&.to_s, known_gaps: definition["known_gaps"]&.to_s
        }
        data[:asset_notes] = Catalog.notes_for_term(name) if notes
        data[:links] = { self: "/v1/dictionary/#{name}", docs: "#{Catalog::DICTIONARY_DOCS}/#{name}" }
        data
      end

      def scalar(value) = value.is_a?(String) || value.is_a?(Integer) || value == true || value == false ? value : value.to_s
    end
  end
end
