module Mcp
  module Tools
    # describe_data: GET /v1/spending/sources, /v1/datasets and /v1/dictionary,
    # and the caveat catalogue, by topic.
    class DescribeData < Base
      tool_name "describe_data"
      title "Describe the data"
      KINDS = %w[spending_semantics source dataset term caveat datasets caveats search].freeze
      SEMANTICS = /\A(spending( semantics)?|semantics|amounts?|totals?|totalling|sum(ming)?|measures?|money)\z/

      GUIDANCE = <<~TEXT.squish.freeze
        Each spending source publishes a different measure of money, and the sources overlap (the same grant can
        appear in proactive disclosure and in the Public Accounts), so amounts from different sources must never be
        added: report each source separately and name its measure. Within one source, rows sharing a canonical_id
        are revisions of one agreement: count only the latest (latest_revision_only, as entity_spending's summary
        does). Aggregate rows (is_aggregated) bundle many small payments and are left out of summaries. A blank
        amount is unknown, not zero. Fiscal years run April to March and are written 2024-25. Totals cover rows
        linked to an entity only; unlinked rows that name it are counted separately. Amounts are decimal strings
        with an ISO 4217 currency. Cite the record's cite, or for a computed number the operation URL with as_of,
        and state the release.
      TEXT

      description <<~TEXT.squish
        Explain what the data means before you use it: what a spending source records and what its amount
        measures, what a field means (the data dictionary), what a caveat code in meta.caveats asks you to do, and
        what each dataset covers (publisher, licence, fiscal years, rows, bulk files). Amounts from different
        sources overlap; never add them. Call describe_data("spending semantics") before totalling or comparing
        amounts: sources also measure different things (agreement values are not payments). topic can be "spending semantics", a source key (proactive_grants), a dataset asset key
        (sources/ca/tbs/proactive_grants), a dictionary term (fiscal_year, canonical_id), a caveat code
        (agreement_value_not_paid), "datasets", "caveats", or any words to search the dictionary. Costs 1 to 2
        request units.
      TEXT
      input_schema(
        properties: {
          topic: { type: "string", minLength: 2, maxLength: 200,
                   description: "\"spending semantics\", a source key, an asset key, a dictionary term, a caveat code, \"datasets\", \"caveats\", or words to search for." },
          as_of: Arguments.as_of("listSpendingSources")
        },
        required: [ "topic" ]
      )
      output_schema Schemas.output(
        properties: {
          "topic" => { "type" => "string" },
          "kind" => { "type" => "string", "enum" => KINDS, "description" => "How the topic was read." },
          "release" => { "type" => [ "integer", "null" ], "description" => "The release that answered, when a release-bound lookup ran." },
          "guidance" => { "type" => [ "string", "null" ], "description" => "Rules for using the data, for spending semantics." },
          "sources" => { "type" => "array", "items" => Schemas.ref("SpendingSource") },
          "datasets" => { "type" => "array", "items" => Schemas.ref("Dataset") },
          "terms" => { "type" => "array", "items" => Schemas.ref("DictionaryTerm") },
          "caveats" => { "type" => "array", "items" => Schemas.ref("Caveat") },
          "citations" => { "type" => "array", "items" => { "type" => "string" } }
        },
        required: %w[topic kind release guidance sources datasets terms caveats citations]
      )

      # Values for caveat texts that take them, when a caveat is described
      # rather than raised by a response.
      PLACEHOLDERS = { count: "N", url: "the unlinked link in the response", detail: "Coverage is partial." }.freeze

      def self.perform(ctx, topic:, as_of: nil)
        key = topic.to_s.strip
        normal = key.downcase.squish
        result = { "topic" => topic, "release" => nil, "guidance" => nil, "sources" => [], "datasets" => [], "terms" => [], "caveats" => [] }
        catalog = PublicApi::Catalog
        if normal.match?(SEMANTICS)
          sources = list(ctx, "/v1/spending/sources", "listSpendingSources", as_of:)
          result.merge!("kind" => "spending_semantics", "guidance" => GUIDANCE, "sources" => sources.body["data"], "release" => release_of(sources.body),
            "caveats" => %w[not_cross_source_total revisions_listed latest_revision_only aggregates_excluded amount_missing linked_only].map { |c| caveat(c) })
        elsif catalog.source(normal)
          sources = list(ctx, "/v1/spending/sources", "listSpendingSources", as_of:)
          source = sources.body["data"].find { |s| s["source"] == normal }
          dataset = source && get(ctx, "/v1/datasets/#{ERB::Util.url_encode(source['asset'])}", "getDataset", as_of: release_of(sources.body))
          result.merge!("kind" => "source", "sources" => [ source ].compact, "datasets" => [ dataset&.body&.dig("data") ].compact, "release" => release_of(sources.body),
            "caveats" => Array(source&.dig("caveats")))
        elsif key.include?("/")
          dataset = expect_ok!(get(ctx, "/v1/datasets/#{ERB::Util.url_encode(key)}", "getDataset", as_of:)).body
          result.merge!("kind" => "dataset", "datasets" => [ dataset["data"] ], "release" => release_of(dataset), "caveats" => dataset.dig("data", "caveats"))
        elsif catalog.definition(normal) && normal.match?(PublicApi::V1::DictionaryController::TERM)
          term = expect_ok!(get(ctx, "/v1/dictionary/#{normal}", "getDictionaryTerm")).body
          result.merge!("kind" => "term", "terms" => [ term["data"] ])
        elsif catalog.caveat_texts.key?(normal)
          result.merge!("kind" => "caveat", "caveats" => [ caveat(normal) ])
        elsif normal == "datasets"
          datasets = list(ctx, "/v1/datasets", "listDatasets", as_of:, limit: 50)
          result.merge!("kind" => "datasets", "datasets" => datasets.body["data"], "release" => release_of(datasets.body))
        elsif normal == "caveats"
          result.merge!("kind" => "caveats", "caveats" => catalog.caveat_texts.keys.sort.map { |c| caveat(c) })
        else
          terms = list(ctx, "/v1/dictionary", "listDictionaryTerms", q: normal, limit: 10)
          result.merge!("kind" => "search", "terms" => terms.body["data"],
            "caveats" => catalog.caveat_texts.keys.select { |c| c.include?(normal.tr(" ", "_")) }.sort.map { |c| caveat(c) })
        end
        result.merge("citations" => citations(result))
      end

      def self.list(ctx, path, operation, **params) = expect_ok!(ctx.api.get(path, operation:, **params))

      def self.get(ctx, path, operation, **params) = ctx.api.get(path, operation:, **params)

      def self.caveat(code)
        PublicApi::Catalog.caveat(code, **PLACEHOLDERS.slice(*placeholders(code)))
      end

      def self.placeholders(code) = PublicApi::Catalog.caveat_texts.fetch(code).fetch("en").scan(/%\{(\w+)\}/).flatten.map(&:to_sym)

      def self.citations(result)
        sources = result["sources"].map { |s| "#{s['publisher']}, #{s['title']} (#{s['license']}); Build Canada source #{s['source']}" }
        datasets = result["datasets"].map { |d| "#{[ d['publisher'], d['title'] ].compact.join(', ')} (#{d['license']}), https://data.buildcanada.com#{d.dig('links', 'self')}" }
        terms = result["terms"].map { |t| "Build Canada data dictionary, #{t['term']}: #{t.dig('links', 'docs')}" }
        caveats = result["caveats"].map { |c| c["docs"] }.compact
        (sources + datasets + terms + caveats).uniq
      end

      def self.summary(result)
        lines = []
        lines << result["guidance"] if result["guidance"]
        result["sources"].each do |s|
          lines << "#{s['source']} (#{s['publisher']}, #{s['title']}): measure #{s['measure']}. #{s['amount_note']} Revisions: #{s['revisions_note']}"
        end
        result["datasets"].each do |d|
          coverage = d["coverage"] || {}
          years = [ coverage["from_fiscal_year"], coverage["to_fiscal_year"] ].compact.join(" to ")
          lines << "Dataset #{d['asset_key']}: #{d['title']}. #{d['record_meaning']} Rows: #{coverage['rows'] || 'unknown'}#{", fiscal years #{years}" if years.present?}."
        end
        result["terms"].each do |t|
          extra = [ t["units"] && "Units: #{t['units']}.", t["blank_means"] && "Blank means: #{t['blank_means']}." ].compact.join(" ")
          lines << "#{t['term']}: #{t['meaning']} #{extra}".strip
        end
        lines << "Caveats:" << caveat_lines(result["caveats"]) if result["caveats"].any?
        lines << "Nothing matched \"#{result['topic']}\". Try \"spending semantics\", \"datasets\" or \"caveats\"." if lines.empty?
        lines.flatten.join("\n")
      end
    end
  end
end
