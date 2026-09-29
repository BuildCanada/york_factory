require "digest"
require "json"

# Rows of a small fact-factory read model (the `api` schema) with two
# releases, 10 and 11, for the public API tests. Each row is written the way
# fact-factory's read model build writes it (serve/read_model.py), and the
# spending summary is built by fact-factory's own SUMMARY_SQL
# (FactFactoryApiDatabase), so the summary rules are fact-factory's, not a
# copy of them.
#
# What the rows exercise:
# - release pinning: Diamond Valley gains an alias and grant G1 a second
#   amendment in release 11; entity NEW exists only in release 11;
# - redirects (DUP -> FOUNDATION), lineage (BLACK_DIAMOND and TURNER_VALLEY
#   amalgamated into DIAMOND_VALLEY), relationships in and out;
# - read:persons gating (PERSON, and its director_of relationship, never served
#   in phase 1);
# - spending: revisions, an aggregate row, a blank amount, an archive copy,
#   linked, proposed and unlinked occurrences, two currencies, and the privacy
#   rules: an individual recipient's full postal code (which must leave as its
#   FSA) and an address key in entity attributes (which must never leave).
module FactFactoryApiFixtures
  DIAMOND_VALLEY = "01J9ZK4T6M8Q2R5V7X3B1N0C4D".freeze
  HERITAGE = "01J9ZK3A1B2C3D4E5F6G7H8J9K".freeze
  FOUNDATION = "01JA2B3C4D5E6F7G8H9J0K1M2N".freeze
  BLACK_DIAMOND = "01H8BD0000000000000000000A".freeze
  TURNER_VALLEY = "01H8TV0000000000000000000A".freeze
  DUP = "01JB00000000000000000000D9".freeze
  NEW = "01JC00000000000000000000NW".freeze
  PERSON = "01JD0000000000000000000PRS".freeze
  ALBERTA = "01H7AB00000000000000000000".freeze
  UNKNOWN = "01JZZZZZZZZZZZZZZZZZZZZZZZ".freeze

  GRANTS = "sources/ca/tbs/proactive_grants".freeze
  TRANSFERS = "sources/ca/pspc/transfer_payments".freeze
  CONTRACTS = "sources/ca/tbs/proactive_contracts".freeze
  GAC = "sources/ca/gac/iati_activities".freeze

  ROSTER_SHA = "388298822179d1c949ea92a24e651d6025055e90a421202f008931b7724167ea".freeze
  GRANTS_SHA = "0d9b2894a8cae9a90053f339b2aeb87245a6d5c123ab12c1117640b735b78f21".freeze
  SNAPSHOTS = {
    10 => { GRANTS => "2400000000000000001", TRANSFERS => "7718203349911205548", CONTRACTS => "8800000000000000001",
            GAC => "9900000000000000001", "#{GRANTS}@archive_import" => "1100000000000000001" },
    11 => { GRANTS => "2534519102996296639", TRANSFERS => "7718203349911205548", CONTRACTS => "8800000000000000001",
            GAC => "9900000000000000001", "#{GRANTS}@archive_import" => "1100000000000000001" }
  }.freeze

  # Spending keys (26 Crockford base32 characters).
  G1_A0 = "K3M9Q2W7XA4B8C1D5E6F0G2H3J".freeze
  G1_A1 = "K3M9Q2W7XA4B8C1D5E6F0G2H3K".freeze
  G2 = "K3M9Q2W7XA4B8C1D5E6F0G2H3M".freeze
  G_PERSON = "K3M9Q2W7XA4B8C1D5E6F0G2H3N".freeze
  G_AGGREGATE = "K3M9Q2W7XA4B8C1D5E6F0G2H3P".freeze
  G_BLANK = "K3M9Q2W7XA4B8C1D5E6F0G2H3Q".freeze
  G_ARCHIVE = "K3M9Q2W7XA4B8C1D5E6F0G2H3R".freeze
  G_PROPOSED = "K3M9Q2W7XA4B8C1D5E6F0G2H3S".freeze
  T1 = "T7M9Q2W7XA4B8C1D5E6F0G2H3J".freeze
  T2 = "T7M9Q2W7XA4B8C1D5E6F0G2H3K".freeze
  C1 = "C7M9Q2W7XA4B8C1D5E6F0G2H3J".freeze
  GAC1 = "GAM9Q2W7XA4B8C1D5E6F0G2H3J".freeze

  module_function

  def sha(*parts) = Digest::SHA256.hexdigest(parts.join("|"))

  def tables
    @tables ||= {
      "releases" => releases,
      "entities" => entities,
      "entity_names" => entity_names,
      "identifiers" => identifiers,
      "relationships" => relationships,
      "spending_records" => spending_records,
      "spending_parties" => spending_parties,
      "release_exports" => release_exports
    }
  end

  # ---------- registry ----------

  def roster_source(row) = { origin: "roster", source_key: "ca-ab/municipal_affairs/municipalities", capture_sha256: ROSTER_SHA,
                             capture_url: "https://files.buildcanada.com/sha256/38/#{ROSTER_SHA}", row_number: row }

  def entity(entity_id, name, from:, to: nil, **attrs)
    {
      row_id: sha("entity", entity_id, from), entity_id:, anchor: attrs.delete(:anchor) || "test:#{entity_id}",
      entity_class: "organization", subtype: nil, name:, name_fr: nil, aliases: [], jurisdiction: "ca", status: "active",
      valid_from: nil, valid_to: nil, attributes: {}, redirected_to: nil, content_sha256: sha("content", entity_id, from),
      source: { origin: "resolution" }, recorded_at: 1_758_823_331.0 + from, release_from: from, release_to: to
    }.merge(attrs)
  end

  def entities
    dv = { entity_class: "government_org", subtype: "municipal_government", jurisdiction: "ca-ab", valid_from: "2023-01-01",
           anchor: "ca-ab/municipal_affairs/municipalities:0417", source: roster_source(212),
           # An address key the read model would have removed (serve/allowlist.FORBIDDEN_KEYS): the API must never serve it.
           attributes: { municipality_type_raw: "Town", office: { mailing_address: "Box 1, Diamond Valley" } } }
    [
      entity(DIAMOND_VALLEY, "Town of Diamond Valley", from: 10, to: 11, **dv),
      entity(DIAMOND_VALLEY, "Town of Diamond Valley", from: 11, **dv, aliases: [ "Diamond Valley" ]),
      entity(HERITAGE, "Canadian Heritage", from: 10, entity_class: "government_org", subtype: "ministerial_department",
        name_fr: "Patrimoine canadien", attributes: { institutional_form: "Ministerial department" }, source: roster_source(40)),
      entity(FOUNDATION, "Diamond Valley Community Foundation", from: 10, subtype: "registered_charity", jurisdiction: "ca-ab"),
      entity(BLACK_DIAMOND, "Town of Black Diamond", from: 10, entity_class: "government_org", subtype: "municipal_government",
        jurisdiction: "ca-ab", valid_from: "1956", valid_to: "2022-12-31", status: "dissolved", source: roster_source(18)),
      entity(TURNER_VALLEY, "Town of Turner Valley", from: 10, entity_class: "government_org", subtype: "municipal_government",
        jurisdiction: "ca-ab", valid_from: "1977-06", valid_to: "2022-12-31", status: "dissolved", source: roster_source(311)),
      entity(DUP, "Diamond Valley Community Fdn", from: 10, subtype: "registered_charity", jurisdiction: "ca-ab",
        status: "redirected", redirected_to: FOUNDATION),
      entity(NEW, "Diamond Valley Arts Society", from: 11, subtype: "non_profit", jurisdiction: "ca-ab"),
      entity(PERSON, "Jane Q. Example", from: 10, entity_class: "person", subtype: nil, jurisdiction: nil),
      entity(ALBERTA, "Alberta", from: 10, entity_class: "jurisdiction", subtype: "province", jurisdiction: "ca-ab")
    ]
  end

  # Names, French names and aliases per entity version, keyed the way
  # fact-factory keys them (FactFactory::Names is the port of names.py).
  def entity_names
    entities.flat_map do |e|
      [ [ "name", e[:name] ], [ "name_fr", e[:name_fr] ], *e[:aliases].map { |a| [ "alias", a ] } ].filter_map do |kind, value|
        next if value.nil?

        { row_id: e[:row_id], entity_id: e[:entity_id], kind:, name: value, normalized_name: FactFactory::Names.normalize(value),
          match_key: FactFactory::Names.match_key(value), normalization: FactFactory::Names::NORMALIZATION_VERSION,
          release_from: e[:release_from], release_to: e[:release_to] }
      end
    end
  end

  def identifier(entity_id, namespace, value, from:, to: nil, verified: 1, vintage: nil)
    { row_id: sha("identifier", entity_id, namespace, value, from), entity_id:, namespace:, value:, verified:, vintage:,
      valid_from: nil, valid_to: nil, content_sha256: sha("identifier-content", entity_id, value), source: roster_source(212),
      recorded_at: 1_758_823_331.0, release_from: from, release_to: to }
  end

  def identifiers
    [
      identifier(DIAMOND_VALLEY, "ca.statcan.csd_uid", "4806014", from: 10, vintage: "2021"),
      identifier(FOUNDATION, "ca.cra.bn9", "107511586", from: 10),
      identifier(FOUNDATION, "ca.cra.bn15", "107511586RR0001", from: 10),
      identifier(NEW, "ca.cra.bn9", "107511586", from: 11, verified: 0),
      identifier(PERSON, "ca.cra.bn9", "999999999", from: 10)
    ]
  end

  def relationship(subject_id, predicate, object_id: nil, object_ref: nil, from: 10, attributes: {}, valid_from: nil, valid_to: nil)
    { row_id: sha("relationship", subject_id, predicate, object_id || object_ref, from), subject_id:, predicate:, object_id:, object_ref:,
      attributes:, valid_from:, valid_to:, content_sha256: sha("relationship-content", subject_id, predicate), source: roster_source(212),
      recorded_at: 1_758_823_331.0, release_from: from, release_to: nil }
  end

  def relationships
    amalgamation = { event: "amalgamated", effective_date: "2023-01-01", authority: "Order in Council 312/2022",
                     citations: [ { locator: "https://kings-printer.alberta.ca/", sha256: GRANTS_SHA, pinpoint: "s. 1" } ] }
    [
      relationship(BLACK_DIAMOND, "succeeded_by", object_id: DIAMOND_VALLEY, attributes: amalgamation, valid_from: "2023-01-01"),
      relationship(TURNER_VALLEY, "succeeded_by", object_id: DIAMOND_VALLEY, attributes: amalgamation, valid_from: "2023-01-01"),
      relationship(DIAMOND_VALLEY, "located_within", object_ref: "ca.statcan.dguid:2021A00054806014",
        attributes: { dguid: "2021A00054806014", vintage: "2021", street_address: "never served" }),
      relationship(DIAMOND_VALLEY, "located_within", object_id: ALBERTA, valid_from: "2023-01-01"),
      relationship(FOUNDATION, "located_within", object_id: DIAMOND_VALLEY, valid_from: "2010", valid_to: "2019-03"),
      relationship(PERSON, "director_of", object_id: FOUNDATION)
    ]
  end

  # ---------- spending ----------

  def record(spending_key, asset_key, id, from: 10, to: nil, acquisition: "live", **attrs)
    source_key = { GRANTS => "proactive_grants", TRANSFERS => "transfer_payments", CONTRACTS => "proactive_contracts", GAC => "global_affairs_projects" }.fetch(asset_key)
    {
      spending_key:, asset_key:, source_key:, acquisition:, resource_id: sha("resource", asset_key, acquisition), id: sha("row", id),
      external_id: sha("external", id), canonical_id: sha("canonical", id), source_occurrence: 1, record_type: "grant",
      title: nil, description: nil, program: nil, payer: "Canadian Heritage", payer_code: "pch", recipient: nil, recipients: [],
      recipient_refs: [], research_org: nil, principal_investigator: nil, recipient_business_number: nil, recipient_type: nil,
      recipient_city: nil, recipient_postal_code: nil, province: "AB", country: "CA", amount: nil, currency: "CAD",
      commitments_json: nil, fiscal_year: nil, date: nil, date_raw: nil, is_aggregated: false, value_consistent: nil,
      revision_rank: nil, source_url: "https://open.canada.ca/data/dataset/432527ab/resource/1d15a62f", source_sha256: GRANTS_SHA,
      parser_version: "spending-iceberg-v5", snapshot_id: SNAPSHOTS.fetch(from).fetch(acquisition == "live" ? asset_key : "#{asset_key}@#{acquisition}"),
      content_sha256: sha("record-content", spending_key), release_from: from, release_to: to
    }.merge(attrs)
  end

  def spending_records
    g1 = { canonical_id: sha("canonical", "g1"), title: "Canada Cultural Spaces Fund", program: "Canada Cultural Spaces Fund",
           recipient: "Town of Diamond Valley", recipient_city: "Diamond Valley", recipient_postal_code: "T0L 0H0",
           recipient_type: "G", record_type: "contribution", fiscal_year: 2024 }
    [
      record(G1_A0, GRANTS, "g1a0", **g1, amount: "125000.00", date: "2024-06-01", date_raw: "2024-06-01", revision_rank: [ 0 ]),
      record(G1_A1, GRANTS, "g1a1", from: 11, **g1, amount: "150000.00", date: "2024-09-01", date_raw: "2024-09-01", revision_rank: [ 1 ]),
      record(G2, GRANTS, "g2", title: "Community foundation operating grant", recipient: "Diamond Valley Community Foundation",
        recipient_postal_code: "T0L 1A0", amount: "50000.00", fiscal_year: 2023, date: "2023-05-01", revision_rank: [ 0 ],
        recipient_business_number: "107511586RR0001"),
      # An individual recipient: the read model reduces the postal code to its FSA; this row keeps the full code to prove the API
      # reduces it again.
      record(G_PERSON, GRANTS, "gp", title: "Artist residency", recipient: "Jane Doe", recipient_city: "Calgary",
        recipient_postal_code: "T2P 1J9", recipient_type: "P", amount: "5000.00", fiscal_year: 2024, revision_rank: [ 0 ]),
      record(G_AGGREGATE, GRANTS, "gagg", title: "Grants under $25,000", recipient: "Town of Diamond Valley", is_aggregated: true,
        amount: "1000.00", fiscal_year: 2024, revision_rank: [ 0 ]),
      record(G_BLANK, GRANTS, "gblank", title: "Heritage signage", recipient: "Town of Diamond Valley", amount: nil, fiscal_year: 2025,
        revision_rank: [ 0 ]),
      record(G_ARCHIVE, GRANTS, "g1a0", acquisition: "archive_import", **g1, amount: "125000.00", date: "2024-06-01", revision_rank: [ 0 ]),
      record(G_PROPOSED, GRANTS, "gprop", title: "Rink roof", recipient: "Diamond Valley (Town)", amount: "30000.00", fiscal_year: 2024,
        revision_rank: [ 0 ]),
      record(T1, TRANSFERS, "t1", record_type: "transfer_payment", payer_code: nil, recipient: "TOWN OF DIAMOND VALLEY", amount: "880000.00",
        fiscal_year: 2024, canonical_id: sha("external", "t1")),
      record(T2, TRANSFERS, "t2", record_type: "transfer_payment", payer_code: nil, recipient: "Town of Diamond Valley", amount: "12000.00",
        fiscal_year: 2023, canonical_id: sha("external", "t2")),
      record(C1, CONTRACTS, "c1", record_type: "contract", title: "Hall rental", recipient: "Diamond Valley Community Foundation",
        recipient_postal_code: "T0L 1A0", amount: "20000.00", fiscal_year: 2024, value_consistent: true, revision_rank: [ 0 ]),
      record(GAC1, GAC, "gac1", record_type: "project", payer: "Global Affairs Canada", payer_code: "dfatd-maecd", currency: nil,
        recipients: [ "Org A", "Org B" ], recipient_refs: [ "XM-DAC-1", nil ], commitments_json: { "CAD" => 100.0, "USD" => 50.5 },
        fiscal_year: 2024, date: "2024-04-15")
    ]
  end

  def party(spending_key, field, name, entity_id: nil, kind: "organization", reason: nil, method: nil, candidates: nil, from: nil, position: 0)
    r = spending_records.find { |x| x[:spending_key] == spending_key }
    method ||= entity_id ? (field == "payer" ? "payer_code" : "exact_name") : nil
    reason ||= entity_id ? nil : "no_candidate"
    {
      row_id: sha("party", spending_key, field, position), occurrence_id: sha("occurrence", r[:asset_key], r[:acquisition], r[:id], field, position),
      asset_key: r[:asset_key], acquisition: r[:acquisition], snapshot_id: r[:snapshot_id], spending_row_id: r[:id], field:, position:,
      party_kind: kind, kind_reason: nil, raw_name: name, normalized_name: FactFactory::Names.normalize(name), identifiers: {},
      city: "Diamond Valley", province: "ab", fsa: "T0L", country: "CA", row_date: nil, fiscal_year: r[:fiscal_year], entity_id:,
      method:, reason:, candidates: candidates || [], create_reason: nil, rule_version: "resolution-v5+occurrences-v3+names-v2+matching-v4",
      content_sha256: sha("party-content", spending_key, field), recorded_at: 1_758_823_331.0, release_from: from || r[:release_from],
      release_to: nil
    }
  end

  def spending_parties
    heritage = ->(key) { party(key, "payer", "Canadian Heritage", entity_id: HERITAGE) }
    [
      heritage.(G1_A0), party(G1_A0, "recipient", "Town of Diamond Valley", entity_id: DIAMOND_VALLEY),
      heritage.(G1_A1), party(G1_A1, "recipient", "Town of Diamond Valley", entity_id: DIAMOND_VALLEY),
      heritage.(G2), party(G2, "recipient", "Diamond Valley Community Foundation", entity_id: FOUNDATION, method: "identifier"),
      heritage.(G_PERSON), party(G_PERSON, "recipient", "Jane Doe", kind: "individual", reason: "excluded_individual"),
      heritage.(G_AGGREGATE), party(G_AGGREGATE, "recipient", "Town of Diamond Valley", entity_id: DIAMOND_VALLEY),
      heritage.(G_BLANK), party(G_BLANK, "recipient", "Town of Diamond Valley", entity_id: DIAMOND_VALLEY),
      party(G_ARCHIVE, "payer", "Canadian Heritage", entity_id: HERITAGE),
      party(G_ARCHIVE, "recipient", "Town of Diamond Valley", entity_id: DIAMOND_VALLEY),
      heritage.(G_PROPOSED),
      party(G_PROPOSED, "recipient", "Diamond Valley (Town)", reason: "proposed", method: "exact_name", candidates: [ DIAMOND_VALLEY ]),
      party(T1, "payer", "Canadian Heritage", entity_id: HERITAGE, method: "payer_name"),
      party(T1, "recipient", "TOWN OF DIAMOND VALLEY", entity_id: DIAMOND_VALLEY),
      party(T2, "payer", "Canadian Heritage", entity_id: HERITAGE, method: "payer_name"),
      # Unlinked, but with Diamond Valley's normalized name: counted in the summary's unlinked_occurrences.
      party(T2, "recipient", "Town of Diamond Valley", reason: "period_spans_change", candidates: [ DIAMOND_VALLEY, BLACK_DIAMOND ]),
      heritage.(C1), party(C1, "vendor_name", "Diamond Valley Community Foundation", entity_id: FOUNDATION),
      party(GAC1, "payer", "Global Affairs Canada", reason: "no_candidate"),
      party(GAC1, "recipients", "Org A", reason: "no_candidate"),
      party(GAC1, "recipients", "Org B", reason: "no_candidate", position: 1)
    ]
  end

  # ---------- releases ----------

  def releases
    [ 10, 11 ].map do |n|
      rows = ->(table) { tables_for_counts[table].count { |r| r[:release_from] == n } }
      closed = ->(table) { tables_for_counts[table].count { |r| r[:release_to] == n } }
      counts = { "previous_release" => n == 10 ? nil : 10 }
      %w[entities identifiers relationships spending_parties entity_names].each { |t| counts[t] = { "added" => rows.(t), "closed" => closed.(t) } }
      snapshots = SNAPSHOTS.fetch(n).to_h do |label, snapshot_id|
        asset, acquisition = label.split("@")
        live = spending_records.count do |r|
          r[:asset_key] == asset && r[:acquisition] == (acquisition || "live") && r[:release_from] <= n && (r[:release_to].nil? || r[:release_to] > n)
        end
        [ label, { "snapshot_id" => snapshot_id, "rows" => live, "duplicates" => 0, "changed" => n == 10 || label == GRANTS } ]
      end
      {
        release_id: n, published_at: n == 10 ? "2026-09-20T06:00:00Z" : "2026-09-27T06:14:02Z",
        built_at: n == 10 ? "2026-09-20T06:30:00Z" : "2026-09-27T06:40:00Z", code_revision: "7a570c2", build_version: "registry-build-v4",
        roster_captures: { "ca-ab/municipal_affairs/municipalities" => [ { "id" => 5, "url" => "https://files.buildcanada.com/sha256/38/#{ROSTER_SHA}", "sha256" => ROSTER_SHA, "rows" => 344 } ] },
        spending_snapshots: snapshots, snapshot_basis: "recorded", counts:,
        checks: { "registry" => [ { "name" => "no_person_entities", "passed" => true, "blocking" => true } ],
                  "api" => [ { "name" => "api_columns_allowlisted", "blocking" => true, "passed" => true },
                             { "name" => "api_summary_reconciles", "blocking" => true, "passed" => true, "detail" => "12 of 12 sampled entities reconcile" } ] },
        build_seconds: 12.5
      }
    end
  end

  def tables_for_counts
    { "entities" => entities, "identifiers" => identifiers, "relationships" => relationships, "spending_parties" => spending_parties,
      "entity_names" => entity_names }
  end

  def release_exports
    %w[entities identifiers manifest.json].map do |table|
      key = table == "manifest.json" ? "releases/11/manifest.json" : "releases/11/#{table}.parquet"
      { release_id: 11, table_name: table, object_key: key, url: nil, sha256: sha("export", table), rows: table == "manifest.json" ? nil : 9,
        bytes: 4096, created_at: "2026-09-27T07:00:00Z" }
    end
  end
end
