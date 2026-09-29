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

      # `parties` are the row's SpendingParty rows (always loaded, for the
      # postal code rule); they are shown only when `show_parties`.
      def record(r, ctx, parties:, latest:, entities:, show_parties:, raw: false, capture: nil)
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
          recipient_postal_code: postal_code(r.recipient_postal_code, parties),
          province: r.province,
          country: r.country,
          amount: Format.amount(r.amount),
          currency: r.currency.to_s.match?(/\A[A-Z]{3}\z/) ? r.currency : nil,
          measure: Catalog::MEASURES.fetch(r.source_key),
          amount_note: source&.amount_note(ctx.dictionary).to_s,
          commitments: commitments(r.commitments_json),
          value_consistent: r.value_consistent,
          fiscal_year: Format.fiscal_year(r.fiscal_year),
          date: r.date&.iso8601,
          date_raw: r.date_raw,
          revision_rank: r.revision_rank.is_a?(Array) ? r.revision_rank : (r.revision_rank.nil? ? nil : [ r.revision_rank ]),
          is_latest_revision: latest ? true : false
        }
        data[:parties] = parties.map { |p| party(p, entities) } if show_parties
        data[:raw] = nil if raw
        data[:provenance] = provenance(r, ctx, source, capture)
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
          # A linked entity the caller may not see (a person, without
          # read:persons) is shown as unlinked-looking nulls, never by name.
          entity_id: entity ? Format.entity_gid(p.entity_id) : nil,
          entity: entity && EntitySerializer.ref(entity),
          method: METHODS.include?(p.method) ? p.method : nil,
          reason: linked ? nil : (REASONS.include?(p.reason) ? p.reason : nil),
          candidates: linked ? [] : Array(p.candidates).map { |c| c.to_s.match?(Format::ULID) ? Format.entity_gid(c) : c.to_s },
          rule_version: p.rule_version
        }
      end

      # The recipient postal code as served (DECISIONS 20): whole only when
      # every recipient party on the row is an organization, else its FSA. The
      # read model already applies this; this is the second guard.
      def postal_code(value, parties)
        return nil if value.nil?

        recipients = parties.select { |p| FactFactory::SpendingQuery::POSTAL_FIELDS.include?(p.field) }
        organization = recipients.any? && recipients.all? { |p| p.party_kind == "organization" }
        organization ? value : Format.fsa(value)
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

      # The release answering, with the Iceberg snapshot it pinned for the
      # row's slice (that snapshot holds the row as served), and the captured
      # source file (api.captures). Spending rows carry no row number yet, so
      # there is no locator (fact-factory SUCKS.md, "CSV rows have no location
      # in the source file").
      def provenance(r, ctx, source, capture = nil)
        snapshot = FactFactory::ReleaseQuery.snapshot_for(ctx.release, asset_key: r.asset_key, acquisition: r.acquisition) || r.snapshot_id
        {
          asset: r.asset_key, release: ctx.release, snapshot_id: snapshot.to_s.match?(/\A\d+\z/) ? snapshot.to_s : nil,
          recorded_at: nil, capture: capture_object(capture), locator: nil, source: nil, parser_version: r.parser_version,
          license: source&.license
        }
      end

      # A Capture, when the capture has everything the contract requires: its
      # source URL and when it was retrieved (blank when fact-factory recorded
      # no retrieval for those bytes).
      def capture_object(capture)
        return nil unless capture && capture.retrieved_at && capture.source_url.present? && Format.sha256(capture.sha256)

        { sha256: capture.sha256, url: "#{FactFactory::DatasetQuery::FILES_BASE}/#{capture.object_key}", source_url: capture.source_url,
          retrieved_at: Format.timestamp(capture.retrieved_at) }
      end

      def cite(r, ctx, source)
        publisher = source ? "#{source.publisher}, #{source.title}" : r.source_key
        digest = r.source_sha256.to_s[0, 8]
        gid = Format.gid("SpendingRecord", r.spending_key)
        if ctx.fr?
          capture = digest.present? ? ", fichier source sha256 #{digest}" : ""
          "#{publisher}#{capture}. Données de Build Canada, version #{ctx.release}, #{gid}."
        else
          capture = digest.present? ? ", source file sha256 #{digest}" : ""
          "#{publisher}#{capture}. Build Canada data release #{ctx.release}, #{gid}."
        end
      end

      def fallback_record_type(source) = source&.record_types&.first || "contract"

      def source_object(source, ctx, snapshot_id:)
        {
          source: source.key, asset: source.asset, title: source.title, publisher: source.publisher,
          measure: source.measure, record_types: source.record_types, amount_note: source.amount_note(ctx.dictionary),
          fiscal_year_note: source.fiscal_year_note(ctx.dictionary), revisions_note: source.revisions_note(ctx.dictionary), license: source.license,
          snapshot_id: snapshot_id.to_s,
          caveats: source.caveats.map { |code| Catalog.caveat(code, locale: ctx.locale) },
          links: {
            dataset: ctx.pin("/v1/datasets/#{ERB::Util.url_encode(source.asset)}"),
            records: Links.url("/v1/spending", { "source" => source.key, "as_of" => ctx.release })
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
