module PublicApi
  module V1
    # SpendingRecord, SpendingParty, SpendingRecordRef, SpendingSource and
    # SpendingSummaryRow (the contract's components/schemas).
    module SpendingSerializer
      RECORD_TYPES = %w[contract grant contribution transfer_payment award project].freeze
      FIELDS = %w[payer recipient recipients principal_investigator research_org vendor_name].freeze
      PARTY_KINDS = %w[organization individual aggregate unknown].freeze
      METHODS = %w[identifier payer_code payer_name exact_name ai_review correction].freeze
      REASONS = %w[excluded_individual excluded_aggregate excluded_unknown conflict ambiguous period_spans_change no_candidate
                   proposed rule_retired ai_undecided corrected_unlinked].freeze
      RECORD_FIELDS = %w[id source record_type is_aggregated external_id canonical_id source_occurrence acquisition resource_id
                         source_row_id title description program payer payer_code recipient recipients recipient_refs
                         principal_investigator research_org recipient_business_number recipient_type recipient_city
                         recipient_postal_code province country amount currency measure amount_note commitments value_consistent
                         fiscal_year date date_raw revision_rank is_latest_revision parties raw provenance cite].freeze

      module_function

      # `parties` are the row's occurrences, shown when given (nil leaves them
      # out); `publication` is the spending_publications row it is in.
      def record(r, ctx, parties:, latest:, entities:, publication:, raw: false)
        source = Catalog.source(r.source_key)
        data = {
          id: Format.gid("SpendingRecord", r.spending_key),
          source: r.source_key,
          record_type: RECORD_TYPES.include?(r.record_type) ? r.record_type : fallback_record_type(source),
          is_aggregated: r.is_aggregated ? true : false,
          external_id: r.external_id.to_s,
          canonical_id: (r.canonical_id.presence || r.external_id).to_s,
          source_occurrence: [ r.source_occurrence.to_i, 1 ].max,
          acquisition: r.acquisition,
          resource_id: r.resource_id,
          source_row_id: r.source_row_id,
          title: r.title,
          description: r.description,
          program: r.program,
          payer: r.payer,
          payer_code: r.payer_code,
          recipient: r.recipient,
          recipients: Array(r.recipients).map(&:to_s),
          recipient_refs: Array(r.recipient_refs).map { |v| v&.to_s },
          principal_investigator: r.principal_investigator,
          research_org: r.research_org,
          recipient_business_number: r.recipient_business_number,
          recipient_type: r.recipient_type,
          recipient_city: r.recipient_city,
          recipient_postal_code: r.recipient_postal_code,
          province: r.province,
          country: r.country,
          amount: Format.amount(r.amount),
          currency: r.currency.to_s.match?(/\A[A-Z]{3}\z/) ? r.currency : nil,
          measure: Catalog::MEASURES.fetch(r.source_key),
          amount_note: source&.amount_note(ctx.dictionary).to_s,
          commitments: commitments(json(r.commitments_json)),
          value_consistent: r.value_consistent,
          fiscal_year: Format.fiscal_year(r.fiscal_year),
          date: r.date&.iso8601,
          date_raw: r.date_raw,
          revision_rank: revision_rank(r.revision_rank_json),
          is_latest_revision: latest ? true : false
        }
        data[:parties] = parties.map { |p| party(p, entities) } if parties
        # The original source record as fact-factory kept it (JSON, or XML for
        # global_affairs_projects).
        data[:raw] = r.raw_json.presence || r.raw_xml.presence if raw
        data[:provenance] = provenance(r, ctx, source, publication)
        data[:cite] = cite(r, ctx, source)
        data
      end

      def ref(r)
        {
          id: Format.gid("SpendingRecord", r.spending_key), source: r.source_key, fiscal_year: Format.fiscal_year(r.fiscal_year),
          amount: Format.amount(r.amount), currency: r.currency.to_s.match?(/\A[A-Z]{3}\z/) ? r.currency : nil,
          payer: r.payer, title: r.title
        }
      end

      def party(p, entities)
        linked = p.entity_id.present?
        status = if linked then "linked"
        elsif p.reason == "proposed" then "proposed"
        else "unlinked"
        end
        entity = linked ? entities[p.entity_id] : nil
        {
          occurrence_id: p.occurrence_id,
          field: FIELDS.include?(p.field) ? p.field : "recipient",
          position: p.position.to_i,
          raw_name: p.raw_name,
          normalized_name: p.normalized_name,
          party_kind: PARTY_KINDS.include?(p.party_kind) ? p.party_kind : "unknown",
          link_status: status,
          entity_id: entity ? Format.entity_gid(p.entity_id) : nil,
          entity: entity && EntitySerializer.ref(entity),
          method: METHODS.include?(p.method) ? p.method : nil,
          reason: linked ? nil : (REASONS.include?(p.reason) ? p.reason : nil),
          candidates: linked ? [] : Array(json(p.candidates)).map { |c| c.to_s.match?(Format::ULID) ? Format.entity_gid(c) : c.to_s },
          rule_version: p.rule_version
        }
      end

      def commitments(value)
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(currency, amount), out|
          formatted = amount.nil? ? nil : Format.amount(amount)
          out[currency.to_s] = formatted if formatted && currency.to_s.match?(/\A[A-Z]{3}\z/)
        rescue ArgumentError
          next
        end
      end

      # The revision answering and the publication it reads the row from: the
      # captured file (content-addressed in R2), the row's position in its
      # parse, and the parser version.
      def provenance(r, ctx, source, publication)
        {
          asset: source&.asset || r.source_key, revision: ctx.revision,
          publication: publication && {
            id: publication.id, version: publication.version, resource_id: publication.resource_id,
            committed_at: Format.timestamp(publication.committed_at)
          },
          recorded_at: nil, capture: capture(r, publication), locator: r.row_number ? { row: r.row_number } : nil, source: nil,
          parser_version: r.parser_version, license: source&.license
        }
      end

      def capture(r, publication)
        sha = Format.sha256(publication&.source_sha256 || r.source_sha256) or return nil

        { sha256: sha, url: Format.capture_url(sha), source_url: (publication&.source_url || r.source_url).presence,
          retrieved_at: Format.timestamp(publication&.observed_at) }
      end

      def cite(r, ctx, source)
        publisher = source ? "#{source.publisher}, #{source.title}" : r.source_key
        digest = r.source_sha256.to_s[0, 8]
        gid = Format.gid("SpendingRecord", r.spending_key)
        if ctx.fr?
          capture = digest.present? ? ", fichier source sha256 #{digest}" : ""
          row = r.row_number ? ", ligne #{r.row_number}" : ""
          "#{publisher}#{capture}#{row}. Données de Build Canada, #{ctx.version_label}, #{gid}."
        else
          capture = digest.present? ? ", source file sha256 #{digest}" : ""
          row = r.row_number ? ", row #{r.row_number}" : ""
          "#{publisher}#{capture}#{row}. Build Canada data #{ctx.version_label}, #{gid}."
        end
      end

      def json(value)
        return value unless value.is_a?(String)

        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end

      def revision_rank(value)
        rank = json(value)
        rank.nil? || rank.is_a?(Array) ? rank : [ rank ]
      end

      def fallback_record_type(source) = source&.record_types&.first || "contract"

      def source_object(source, ctx, version:)
        {
          source: source.key, asset: source.asset, title: source.title, publisher: source.publisher,
          measure: source.measure, record_types: source.record_types, amount_note: source.amount_note(ctx.dictionary),
          fiscal_year_note: source.fiscal_year_note(ctx.dictionary), revisions_note: source.revisions_note(ctx.dictionary), license: source.license,
          version:,
          caveats: source.caveats.map { |code| Catalog.caveat(code, locale: ctx.locale) },
          links: {
            dataset: ctx.pin("/v1/datasets/#{ERB::Util.url_encode(source.asset)}"),
            records: Links.url("/v1/spending", { "source" => source.key, "as_of" => ctx.revision })
          }
        }
      end

      # One SpendingSummaryRow from a summary query row.
      def summary_row(row, counterparty: nil)
        currency = row["currency"].to_s
        {
          source: row["source_key"],
          fiscal_year: Format.fiscal_year(row["fiscal_year"]&.to_i),
          counterparty: counterparty && EntitySerializer.ref(counterparty),
          records: row["records"].to_i,
          agreements: row["agreements"].to_i,
          amount: Format.amount(row["amount"] || 0),
          amount_missing: row["amount_missing"].to_i,
          # A group whose rows have no currency (mixed-currency projects) is
          # XXX, ISO 4217's "no currency": its amount is always 0.00.
          currency: currency.match?(/\A[A-Z]{3}\z/) ? currency : "XXX",
          measure: Catalog::MEASURES.fetch(row["source_key"])
        }
      end
    end
  end
end
