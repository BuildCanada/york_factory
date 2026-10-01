require "digest"
require "json"

# Rows of a small fact-factory database (the fact_factory schema, as
# db/fact_factory/schema.sql creates it) for the public API tests. Each row is
# shaped the way fact-factory writes it: versioned registry rows by revision,
# spending as publications and their records, and the derived tables built by
# fact-factory's own SUMMARY_SQL and COUNTERPARTY_SQL (FactFactoryDatabase).
#
# The registry has these committed revisions:
# - 14: the last batch release, named by snapshot `release-14` (held by the gold
#   set) and pruned by retention; its spending slice is an Iceberg snapshot ID,
#   which no spending table can read;
# - 30: resolved every slice (spending versions 1 to 5) and built the registry;
# - 31: resolved grants again at version 6 (a new parse adding amendment 1 of G1)
#   and changed entities (Diamond Valley's alias, a new entity);
# - 32: committed, but no derived build is at it yet, so it isn't served;
# - 33 is open.
# The derived tables are built at 30 and 31.
#
# What the rows exercise:
# - revision pinning; redirects (DUP -> FOUNDATION); lineage (BLACK_DIAMOND and
#   TURNER_VALLEY amalgamated into DIAMOND_VALLEY); relationships in and out;
# - a person entity, served and listed like any entity, and its director_of
#   relationship, not served until the contract has phase 2's predicates;
# - spending: revisions of one agreement, an aggregate row, a blank amount, an
#   archive copy of a live row, an agreement only the archive has, linked,
#   proposed and unlinked occurrences, an individual recipient (with the postal
#   code as published), and two currencies;
# - elections: one election with two contests, districts with boundaries,
#   candidacies with verified and unverified contacts, a result report.
module FactFactoryFixtures
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
  SOURCE_KEYS = { GRANTS => "proactive_grants", TRANSFERS => "transfer_payments", CONTRACTS => "proactive_contracts",
                  GAC => "global_affairs_projects" }.freeze

  ROSTER_SHA = "388298822179d1c949ea92a24e651d6025055e90a421202f008931b7724167ea".freeze
  GRANTS_SHA = "0d9b2894a8cae9a90053f339b2aeb87245a6d5c123ab12c1117640b735b78f21".freeze
  GRANTS_NEW_SHA = "1d9b2894a8cae9a90053f339b2aeb87245a6d5c123ab12c1117640b735b78f22".freeze
  CONTRACTS_SHA = "c0a7c2a1c3d09f7b3a1ad2d6e1c9b4a0f2e8d7c6b5a4938271605f4e3d2c1b0a".freeze
  ELECTIONS_SHA = "e1ec7100a8cae9a90053f339b2aeb87245a6d5c123ab12c1117640b735b78f21".freeze
  RESULTS_SHA = "e2ec7100a8cae9a90053f339b2aeb87245a6d5c123ab12c1117640b735b78f21".freeze
  ICEBERG_SNAPSHOT = "2534519102996296639".freeze

  # Spending keys (26 Crockford base32 characters).
  G1_A0 = "K3M9Q2W7XA4B8C1D5E6F0G2H3J".freeze
  G1_A1 = "K3M9Q2W7XA4B8C1D5E6F0G2H3K".freeze
  G2 = "K3M9Q2W7XA4B8C1D5E6F0G2H3M".freeze
  G_PERSON = "K3M9Q2W7XA4B8C1D5E6F0G2H3N".freeze
  G_AGGREGATE = "K3M9Q2W7XA4B8C1D5E6F0G2H3P".freeze
  G_BLANK = "K3M9Q2W7XA4B8C1D5E6F0G2H3Q".freeze
  G_ARCHIVE = "K3M9Q2W7XA4B8C1D5E6F0G2H3R".freeze
  G_PROPOSED = "K3M9Q2W7XA4B8C1D5E6F0G2H3S".freeze
  G_ARCHIVE_ONLY = "K3M9Q2W7XA4B8C1D5E6F0G2H3T".freeze
  T1 = "T7M9Q2W7XA4B8C1D5E6F0G2H3J".freeze
  T2 = "T7M9Q2W7XA4B8C1D5E6F0G2H3K".freeze
  C1 = "C7M9Q2W7XA4B8C1D5E6F0G2H3J".freeze
  GAC1 = "GAM9Q2W7XA4B8C1D5E6F0G2H3J".freeze

  # Elections.
  ELECTION = "ca/bc/elections/2024-10-19-general".freeze
  OFFICE = "ca/bc/legislative-assembly/mla".freeze
  DISTRICTS_SET = "ca/bc/electoral-districts/2023".freeze
  ABM = "ca/bc/electoral-districts/2023/abm".freeze
  ABS = "ca/bc/electoral-districts/2023/abs".freeze
  CONTEST_ABM = "#{ELECTION}/mla/abm".freeze
  CONTEST_ABS = "#{ELECTION}/mla/abs".freeze
  CAND_ALEXIS = "01M3TP5P62RM2298Y7AC2WYJJ4".freeze
  CAND_GASPER = "01M3TP5P66PB380KX7FGWHM25G".freeze
  CAND_BANMAN = "01M3TP5P9WM4ZS12V3JW0BZM9Q".freeze
  REPORT = "01M3TP69B6TM9F579VB93ZHFNE".freeze

  T = Time.utc(2026, 9, 30).to_f

  module_function

  def sha(*parts) = Digest::SHA256.hexdigest(parts.join("|"))

  # {table => [row]}, in insertion order.
  def tables
    @tables ||= {
      "registry_revisions" => revisions,
      "registry_snapshots" => snapshots,
      "entities" => entities,
      "entity_identifiers" => identifiers,
      "entity_relationships" => relationships,
      "spending_publications" => publications,
      "spending_records" => spending_records,
      "mention_occurrences" => occurrences,
      "entity_names" => entity_names,
      "derived_builds" => derived_builds,
      "elections_captures" => elections_captures,
      "elections_offices" => [ { id: OFFICE, title: "Member of the Legislative Assembly", title_fr: nil, body_name: "Legislative Assembly of British Columbia",
                                 body_level: "provincial_territorial", jurisdiction: "ca-bc", source_url: "https://elections.bc.ca/" } ],
      "elections_elections" => elections,
      "elections_boundary_sets" => [ { id: DISTRICTS_SET, jurisdiction: "ca-bc", kind: "district", kind_as_shown: "Electoral district",
                                       district_set_id: nil, legal_instrument: "Electoral Districts Act", gazetted_on: nil, in_force_from: "2024-10-19",
                                       in_force_to: nil, source_url: "https://elections.bc.ca/", capture_sha256: ELECTIONS_SHA } ],
      "elections_districts" => districts,
      "elections_contests" => contests,
      "elections_candidacies" => candidacies,
      "elections_candidate_contacts" => contacts,
      "elections_result_reports" => result_reports,
      "elections_results" => results
    }
  end

  # ---------- revisions ----------

  def revisions
    slices30 = { GRANTS => "1", "#{GRANTS}@archive_import" => "2", TRANSFERS => "3", CONTRACTS => "4", GAC => "5" }
    [
      { id: 14, kind: "release", state: "committed", reason: "Registry release 14", inputs: { slices: { GRANTS => ICEBERG_SNAPSHOT } },
        created_at: T - 86_400, committed_at: Time.utc(2026, 9, 29, 6).to_f, pruned_at: T, versions: nil },
      { id: 30, kind: "resolution", state: "committed", reason: "Dagster run a1", inputs: { slices: slices30, activations: "4da24a5b" },
        created_at: T, committed_at: Time.utc(2026, 9, 30, 6).to_f, pruned_at: nil, versions: nil },
      { id: 31, kind: "resolution", state: "committed", reason: "Dagster run a2", inputs: { slices: { GRANTS => "6" } },
        created_at: T + 3600, committed_at: Time.utc(2026, 10, 1, 2, 49, 22).to_f, pruned_at: nil, versions: nil },
      { id: 32, kind: "entities", state: "committed", reason: "Dagster run a3", inputs: {}, created_at: T + 7200,
        committed_at: Time.utc(2026, 10, 1, 4).to_f, pruned_at: nil, versions: nil },
      { id: 33, kind: "resolution", state: "open", reason: "Dagster run a4", inputs: {}, created_at: T + 9000, committed_at: nil,
        pruned_at: nil, versions: nil }
    ]
  end

  def snapshots
    [ { name: "release-14", revision_id: 14, reason: "The last batch release", held_by: "goldset", versions: nil, created_at: T },
      { name: "daily-2026-10-01", revision_id: 31, reason: "Daily", held_by: nil, versions: nil, created_at: T + 4000 } ]
  end

  def derived_builds
    slices = { GRANTS => "1", TRANSFERS => "3", CONTRACTS => "4", GAC => "5" }
    [ { revision_id: 30, previous_revision_id: nil, slices:, counts: { entity_names: { added: 11 } },
        checks: [ { name: "summary_reconciles", blocking: true, passed: true } ], build_version: "derived-v1", built_at: T + 100, build_seconds: 29.8 },
      { revision_id: 31, previous_revision_id: 30, slices: slices.merge(GRANTS => "6"), counts: { entity_names: { added: 3 } },
        checks: [ { name: "summary_reconciles", blocking: true, passed: true } ], build_version: "derived-v1", built_at: T + 3700, build_seconds: 1.7 } ]
  end

  # ---------- registry ----------

  def roster_source(row) = { origin: "roster", source_key: "ca-ab/municipal_affairs/municipalities", capture_sha256: ROSTER_SHA,
                             capture_url: "https://files.buildcanada.com/sha256/38/#{ROSTER_SHA}", row_number: row }

  def entity(entity_id, name, from:, to: nil, **attrs)
    {
      row_id: sha("entity", entity_id, from), entity_id:, anchor: attrs.delete(:anchor) || "test:#{entity_id}",
      entity_class: "organization", subtype: nil, name:, name_fr: nil, aliases: [], jurisdiction: "ca", status: "active",
      valid_from: nil, valid_to: nil, attributes: {}, redirected_to: nil, content_sha256: sha("content", entity_id, from),
      source: { origin: "resolution" }, recorded_at: 1_758_823_331.0 + from, revision_id: from, retired_revision_id: to
    }.merge(attrs)
  end

  def entities
    dv = { entity_class: "government_org", subtype: "municipal_government", jurisdiction: "ca-ab", valid_from: "2023-01-01",
           anchor: "ca-ab/municipal_affairs/municipalities:0417", source: roster_source(212),
           attributes: { municipality_type_raw: "Town", office: { mailing_address: "Box 1, Diamond Valley" } } }
    [
      entity(DIAMOND_VALLEY, "Town of Diamond Valley", from: 30, to: 31, **dv),
      entity(DIAMOND_VALLEY, "Town of Diamond Valley", from: 31, **dv, aliases: [ "Diamond Valley" ]),
      entity(HERITAGE, "Canadian Heritage", from: 30, entity_class: "government_org", subtype: "ministerial_department",
        name_fr: "Patrimoine canadien", attributes: { institutional_form: "Ministerial department" }, source: roster_source(40)),
      entity(FOUNDATION, "Diamond Valley Community Foundation", from: 30, subtype: "registered_charity", jurisdiction: "ca-ab"),
      entity(BLACK_DIAMOND, "Town of Black Diamond", from: 30, entity_class: "government_org", subtype: "municipal_government",
        jurisdiction: "ca-ab", valid_from: "1956", valid_to: "2022-12-31", status: "dissolved", source: roster_source(18)),
      entity(TURNER_VALLEY, "Town of Turner Valley", from: 30, entity_class: "government_org", subtype: "municipal_government",
        jurisdiction: "ca-ab", valid_from: "1977-06", valid_to: "2022-12-31", status: "dissolved", source: roster_source(311)),
      entity(DUP, "Diamond Valley Community Fdn", from: 30, subtype: "registered_charity", jurisdiction: "ca-ab",
        status: "redirected", redirected_to: FOUNDATION),
      entity(NEW, "Diamond Valley Arts Society", from: 31, subtype: "non_profit", jurisdiction: "ca-ab"),
      entity(PERSON, "Jane Q. Example", from: 30, entity_class: "person", subtype: nil, jurisdiction: nil),
      entity(ALBERTA, "Alberta", from: 30, entity_class: "jurisdiction", subtype: "province", jurisdiction: "ca-ab")
    ]
  end

  # entity_names, as fact-factory's derived build writes them (FactFactory::Names
  # is the port of names.py).
  def entity_names
    entities.flat_map do |e|
      [ [ "name", e[:name] ], [ "name_fr", e[:name_fr] ], *e[:aliases].map { |a| [ "alias", a ] } ].filter_map do |kind, value|
        next if value.nil?

        { row_id: e[:row_id], kind:, name: value, entity_id: e[:entity_id], normalized_name: FactFactory::Names.normalize(value),
          match_key: FactFactory::Names.match_key(value), normalization: FactFactory::Names::NORMALIZATION_VERSION,
          revision_id: e[:revision_id], retired_revision_id: e[:retired_revision_id] }
      end
    end
  end

  def identifier(entity_id, namespace, value, from:, to: nil, verified: 1, vintage: nil)
    { row_id: sha("identifier", entity_id, namespace, value, from), entity_id:, namespace:, value:, verified:, vintage:,
      valid_from: nil, valid_to: nil, content_sha256: sha("identifier-content", entity_id, value), source: roster_source(212),
      recorded_at: 1_758_823_331.0, revision_id: from, retired_revision_id: to }
  end

  def identifiers
    [
      identifier(DIAMOND_VALLEY, "ca.statcan.csd_uid", "4806014", from: 30, vintage: "2021"),
      identifier(FOUNDATION, "ca.cra.bn9", "107511586", from: 30),
      identifier(FOUNDATION, "ca.cra.bn15", "107511586RR0001", from: 30),
      identifier(NEW, "ca.cra.bn9", "107511586", from: 31, verified: 0),
      identifier(PERSON, "ca.cra.bn9", "999999999", from: 30)
    ]
  end

  def relationship(subject_id, predicate, object_id: nil, object_ref: nil, from: 30, attributes: {}, valid_from: nil, valid_to: nil)
    { row_id: sha("relationship", subject_id, predicate, object_id || object_ref, from), subject_id:, predicate:, object_id:, object_ref:,
      attributes:, valid_from:, valid_to:, content_sha256: sha("relationship-content", subject_id, predicate), source: roster_source(212),
      recorded_at: 1_758_823_331.0, revision_id: from, retired_revision_id: nil }
  end

  def relationships
    amalgamation = { event: "amalgamated", effective_date: "2023-01-01", authority: "Order in Council 312/2022",
                     citations: [ { locator: "https://kings-printer.alberta.ca/", sha256: GRANTS_SHA, pinpoint: "s. 1" } ] }
    [
      relationship(BLACK_DIAMOND, "succeeded_by", object_id: DIAMOND_VALLEY, attributes: amalgamation, valid_from: "2023-01-01"),
      relationship(TURNER_VALLEY, "succeeded_by", object_id: DIAMOND_VALLEY, attributes: amalgamation, valid_from: "2023-01-01"),
      relationship(DIAMOND_VALLEY, "located_within", object_ref: "ca.statcan.dguid:2021A00054806014",
        attributes: { dguid: "2021A00054806014", vintage: "2021", street_address: "1 Main St" }),
      relationship(DIAMOND_VALLEY, "located_within", object_id: ALBERTA, valid_from: "2023-01-01"),
      relationship(FOUNDATION, "located_within", object_id: DIAMOND_VALLEY, valid_from: "2010", valid_to: "2019-03"),
      relationship(PERSON, "director_of", object_id: FOUNDATION)
    ]
  end

  # ---------- spending ----------

  # Publications: one parse of one resource's capture each. Grants' live
  # resource is parsed twice: version 1 (revision 30) and version 6, which
  # replaces it (revision 31).
  PUBLICATIONS = [
    { id: 101, asset: GRANTS, acquisition: "live", version: 1, replaced_version: 6, sha: GRANTS_SHA },
    { id: 102, asset: GRANTS, acquisition: "archive_import", version: 2, replaced_version: nil, sha: GRANTS_SHA },
    { id: 103, asset: TRANSFERS, acquisition: "live", version: 3, replaced_version: nil, sha: GRANTS_SHA },
    { id: 104, asset: CONTRACTS, acquisition: "live", version: 4, replaced_version: nil, sha: CONTRACTS_SHA },
    { id: 105, asset: GAC, acquisition: "live", version: 5, replaced_version: nil, sha: GRANTS_SHA },
    { id: 106, asset: GRANTS, acquisition: "live", version: 6, replaced_version: nil, sha: GRANTS_NEW_SHA }
  ].freeze

  def resource(asset, acquisition) = sha("resource", asset, acquisition)

  def publications
    PUBLICATIONS.map do |p|
      { id: p[:id], release_id: sha("release", p[:id]), source_key: SOURCE_KEYS.fetch(p[:asset]), acquisition: p[:acquisition],
        resource_id: resource(p[:asset], p[:acquisition]), source_sha256: p[:sha],
        source_url: p[:asset] == CONTRACTS ? nil : "https://open.canada.ca/data/dataset/432527ab/resource/1d15a62f",
        parser_version: "spending-iceberg-v5", observed_at: p[:asset] == CONTRACTS ? nil : Time.utc(2026, 9, 26, 4, 59, 12).to_f + p[:version],
        row_count: rows_of(p[:id]).size, occurrence_copies: 0, content_copies: 0, duplicate_guard: nil, staged_at: T,
        version: p[:version], committed_at: T + p[:version], replaced_version: p[:replaced_version],
        replaced_at: p[:replaced_version] && T + p[:replaced_version], purged_at: nil }
    end
  end

  # [publication id, spending_key, source row id, attributes] per row.
  def row_specs
    g1 = { canonical_id: sha("canonical", "g1"), title: "Canada Cultural Spaces Fund", program: "Canada Cultural Spaces Fund",
           recipient: "Town of Diamond Valley", recipient_city: "Diamond Valley", recipient_postal_code: "T0L 0H0",
           recipient_type: "G", record_type: "contribution", fiscal_year: 2024 }
    g1a0 = { **g1, amount: "125000.00", date: "2024-06-01", date_raw: "2024-06-01", revision_rank_json: "[0]",
             raw_json: '{"ref_number":"001-2024-2025-Q1-00042","amendment_number":"0","agreement_value":"125000.00"}' }
    grants = [
      [ G1_A0, "g1a0", g1a0 ],
      [ G2, "g2", { title: "Community foundation operating grant", recipient: "Diamond Valley Community Foundation",
                   recipient_postal_code: "T0L 1A0", amount: "50000.00", fiscal_year: 2023, date: "2023-05-01", revision_rank_json: "[0]",
                   recipient_business_number: "107511586RR0001" } ],
      # An individual recipient: never linked (individuals are kept out of organization matching).
      [ G_PERSON, "gp", { title: "Artist residency", recipient: "Jane Doe", recipient_city: "Calgary", recipient_postal_code: "T2P 1J9",
                          recipient_type: "P", amount: "5000.00", fiscal_year: 2024, revision_rank_json: "[0]" } ],
      [ G_AGGREGATE, "gagg", { title: "Grants under $25,000", recipient: "Town of Diamond Valley", is_aggregated: true, amount: "1000.00",
                               fiscal_year: 2024, revision_rank_json: "[0]" } ],
      [ G_BLANK, "gblank", { title: "Heritage signage", recipient: "Town of Diamond Valley", amount: nil, fiscal_year: 2025, revision_rank_json: "[0]" } ],
      [ G_PROPOSED, "gprop", { title: "Rink roof", recipient: "Diamond Valley (Town)", amount: "30000.00", fiscal_year: 2024, revision_rank_json: "[0]" } ]
    ]
    g1a1 = [ G1_A1, "g1a1", { **g1, amount: "150000.00", date: "2024-09-01", date_raw: "2024-09-01", revision_rank_json: "[1]" } ]
    rows = grants.map { |key, id, attrs| [ 101, key, id, attrs ] }
    rows += [ grants[0], g1a1, *grants[1..] ].map { |key, id, attrs| [ 106, key, id, attrs ] }
    rows << [ 102, G_ARCHIVE, "g1a0", g1a0 ]
    # An agreement only the archive has: its latest revision across slices.
    rows << [ 102, G_ARCHIVE_ONLY, "garch", { title: "Museum exhibit grant", recipient: "Some Museum", revision_rank_json: "[0]" } ]
    rows << [ 103, T1, "t1", { record_type: "transfer_payment", payer_code: nil, recipient: "TOWN OF DIAMOND VALLEY", amount: "880000.00",
                               fiscal_year: 2024, canonical_id: sha("external", "t1") } ]
    rows << [ 103, T2, "t2", { record_type: "transfer_payment", payer_code: nil, recipient: "Town of Diamond Valley", amount: "12000.00",
                               fiscal_year: 2023, canonical_id: sha("external", "t2") } ]
    rows << [ 104, C1, "c1", { record_type: "contract", title: "Hall rental", recipient: "Diamond Valley Community Foundation",
                               recipient_postal_code: "T0L 1A0", amount: "20000.00", fiscal_year: 2024, value_consistent: true, revision_rank_json: "[0]" } ]
    rows << [ 105, GAC1, "gac1", { record_type: "project", payer: "Global Affairs Canada", payer_code: "dfatd-maecd", currency: nil,
                                   recipients: [ "Org A", "Org B" ], recipient_refs: [ "XM-DAC-1", nil ], commitments_json: '{"CAD": 100.0, "USD": 50.5}',
                                   fiscal_year: 2024, date: "2024-04-15", raw_xml: "<iati-activity><iati-identifier>CA-3-A035529001</iati-identifier></iati-activity>" } ]
    rows
  end

  def rows_of(publication_id) = row_specs.select { |p, *| p == publication_id }

  def spending_records
    row_specs.group_by(&:first).flat_map do |publication_id, specs|
      pub = PUBLICATIONS.find { |p| p[:id] == publication_id }
      specs.each_with_index.map do |(_, key, id, attrs), i|
        {
          publication_id:, row_number: i + 1, id: sha("row", id), spending_key: key, external_id: sha("external", id),
          canonical_id: sha("canonical", id), source_key: SOURCE_KEYS.fetch(pub[:asset]), acquisition: pub[:acquisition],
          resource_id: resource(pub[:asset], pub[:acquisition]), source_url: "https://open.canada.ca/data/dataset/432527ab/resource/1d15a62f",
          source_sha256: pub[:sha], parser_version: "spending-iceberg-v5", record_type: "grant", title: nil, description: nil,
          payer: "Canadian Heritage", payer_code: "pch", recipient: nil, research_org: nil, recipient_business_number: nil,
          recipient_type: nil, recipient_city: nil, recipient_postal_code: nil, currency: "CAD", province: "AB", country: "CA",
          program: nil, principal_investigator: nil, date_raw: nil, raw_json: nil, raw_xml: nil, revision_rank_json: nil,
          commitments_json: nil, extra_json: nil, amount: nil, fiscal_year: nil, source_occurrence: 1, is_aggregated: false,
          value_consistent: nil, date: nil, recipients: [], recipient_refs: []
        }.merge(attrs)
      end
    end
  end

  def label(asset, acquisition) = acquisition == "live" ? asset : "#{asset}@#{acquisition}"

  # One occurrence (mention_occurrences) of a party on the row `key` of `asset`.
  def occurrence(key, field, name, entity_id: nil, kind: "organization", reason: nil, method: nil, candidates: nil, from: 30, position: 0,
                 acquisition: "live")
    spec = row_specs.find { |_, k, *| k == key }
    pub = PUBLICATIONS.find { |p| p[:id] == spec[0] }
    method ||= entity_id ? (field == "payer" ? "payer_code" : "exact_name") : nil
    reason ||= entity_id ? nil : "no_candidate"
    source_key = label(pub[:asset], acquisition)
    {
      row_id: sha("occurrence-row", source_key, key, field, position), occurrence_id: sha("occurrence", source_key, spec[2], field, position),
      source_key:, snapshot_id: pub[:version].to_s, spending_row_id: sha("row", spec[2]), field:, position:, raw_name: name,
      normalized_name: FactFactory::Names.normalize(name), province: "ab", city: "Diamond Valley", postal_code: "T0L 0H0", fsa: "T0L",
      row_date: nil, fiscal_year: spec[3][:fiscal_year], identifiers: {}, party_kind: kind, entity_id:, method:, reason:,
      candidates: candidates || [], roster_refs: nil, rule_version: "resolution-v5+occurrences-v3+names-v2+matching-v4", row_context: nil,
      review_unit_id: nil, fuzzy_candidates: nil, kind_reason: nil, country: "CA", create_unit: nil, create_reason: nil, evidence_sha256: nil,
      content_sha256: sha("occurrence-content", source_key, key, field), source: { origin: "resolution" }, recorded_at: 1_758_823_331.0,
      revision_id: from, retired_revision_id: nil
    }
  end

  def occurrences
    heritage = ->(key, **o) { occurrence(key, "payer", "Canadian Heritage", entity_id: HERITAGE, **o) }
    [
      heritage.(G1_A0), occurrence(G1_A0, "recipient", "Town of Diamond Valley", entity_id: DIAMOND_VALLEY),
      heritage.(G1_A1, from: 31), occurrence(G1_A1, "recipient", "Town of Diamond Valley", entity_id: DIAMOND_VALLEY, from: 31),
      heritage.(G2), occurrence(G2, "recipient", "Diamond Valley Community Foundation", entity_id: FOUNDATION, method: "identifier"),
      heritage.(G_PERSON), occurrence(G_PERSON, "recipient", "Jane Doe", kind: "individual", reason: "excluded_individual"),
      heritage.(G_AGGREGATE), occurrence(G_AGGREGATE, "recipient", "Town of Diamond Valley", entity_id: DIAMOND_VALLEY),
      heritage.(G_BLANK), occurrence(G_BLANK, "recipient", "Town of Diamond Valley", entity_id: DIAMOND_VALLEY),
      heritage.(G_ARCHIVE, acquisition: "archive_import"),
      occurrence(G_ARCHIVE, "recipient", "Town of Diamond Valley", entity_id: DIAMOND_VALLEY, acquisition: "archive_import"),
      heritage.(G_ARCHIVE_ONLY, acquisition: "archive_import"),
      occurrence(G_ARCHIVE_ONLY, "recipient", "Some Museum", reason: "no_candidate", acquisition: "archive_import"),
      heritage.(G_PROPOSED),
      occurrence(G_PROPOSED, "recipient", "Diamond Valley (Town)", reason: "proposed", method: "exact_name", candidates: [ DIAMOND_VALLEY ]),
      occurrence(T1, "payer", "Canadian Heritage", entity_id: HERITAGE, method: "payer_name"),
      occurrence(T1, "recipient", "TOWN OF DIAMOND VALLEY", entity_id: DIAMOND_VALLEY),
      occurrence(T2, "payer", "Canadian Heritage", entity_id: HERITAGE, method: "payer_name"),
      # Unlinked, but with Diamond Valley's normalized name: counted in the summary's unlinked_occurrences.
      occurrence(T2, "recipient", "Town of Diamond Valley", reason: "period_spans_change", candidates: [ DIAMOND_VALLEY, BLACK_DIAMOND ]),
      heritage.(C1), occurrence(C1, "vendor_name", "Diamond Valley Community Foundation", entity_id: FOUNDATION),
      occurrence(GAC1, "payer", "Global Affairs Canada", reason: "no_candidate"),
      occurrence(GAC1, "recipients", "Org A", reason: "no_candidate"),
      occurrence(GAC1, "recipients", "Org B", reason: "no_candidate", position: 1)
    ]
  end

  # ---------- elections ----------

  def elections_captures
    [ [ ELECTIONS_SHA, "candidates", "https://elections.bc.ca/2024-provincial-general-election/candidates/" ],
      [ RESULTS_SHA, "results", "https://elections.bc.ca/2024-provincial-general-election/results/" ] ].map do |sha, kind, url|
      { sha256: sha, kind:, url:, bytes: 4096, content_type: "text/html", first_retrieved_at: T, last_retrieved_at: T + 60, metadata: {} }
    end
  end

  def elections
    [ { id: ELECTION, jurisdiction: "ca-bc", administrator: "Elections BC", kind: "general", called_on: "2024-09-21", voting_day: "2024-10-19",
        return_day: nil, nominations_close_at: "2024-09-28T13:00:00-07:00", registration_deadline_at: nil, mail_request_deadline_at: nil,
        mail_return_deadline_at: nil, advance_voting_starts_at: "2024-10-10", advance_voting_ends_at: "2024-10-15", polls_open_at: nil,
        polls_close_at: nil, voting_notes: nil, where_to_vote_url: nil, source_url: "https://elections.bc.ca/2024-provincial-general-election/",
        capture_sha256: ELECTIONS_SHA },
      { id: "ca/bc/elections/2026-10-24-general", jurisdiction: "ca-bc", administrator: "Elections BC", kind: "general", called_on: nil,
        voting_day: "2026-10-24", source_url: nil, capture_sha256: nil } ]
  end

  def districts
    [ { id: ABM, boundary_set_id: DISTRICTS_SET, code: "ABM", name_as_shown: "Abbotsford-Mission",
        geometry: "SRID=4326;MULTIPOLYGON(((-122.3 49.1,-122.2 49.1,-122.2 49.2,-122.3 49.1)))" },
      { id: ABS, boundary_set_id: DISTRICTS_SET, code: "ABS", name_as_shown: "Abbotsford South", geometry: nil } ]
  end

  def contests
    [ CONTEST_ABM, CONTEST_ABS ].zip([ ABM, ABS ]).map do |id, district|
      { id:, election_id: ELECTION, office_id: OFFICE, district_id: district, seats: 1, method: "fptp", status: "decided", voting_day: nil,
        question_number: nil, question_text: nil, question_text_fr: nil, threshold_as_shown: nil }
    end
  end

  def candidacies
    base = { legal_name: nil, incumbent: nil, residence_address: nil, residence_city: nil, residence_province: nil,
             residence_postal_code: nil, agents: [], declared_result: nil, first_seen_capture: ELECTIONS_SHA,
             last_seen_capture: ELECTIONS_SHA, status_changed_at: nil, person_id: nil }
    [
      base.merge(id: CAND_ALEXIS, contest_id: CONTEST_ABM, ballot_name: "Alexis, Pam", normalized_name: "alexis pam", party_key: "bc-ndp",
        party_as_shown: "BC NDP", status: "accepted", incumbent: true, declared_result: "elected",
        residence_address: "123 Main Street", residence_city: "Mission", residence_province: "BC", residence_postal_code: "V2V 1A1",
        agents: [ { name: "Sam Agent", role: "official_agent" } ]),
      base.merge(id: CAND_GASPER, contest_id: CONTEST_ABM, ballot_name: "Gasper, Reann", normalized_name: "gasper reann",
        party_key: "conservative-party-of-bc", party_as_shown: "Conservative Party of BC", status: "accepted"),
      base.merge(id: CAND_BANMAN, contest_id: CONTEST_ABS, ballot_name: "Banman, Bruce", normalized_name: "banman bruce",
        party_key: "conservative-party-of-bc", party_as_shown: "Conservative Party of BC", status: "accepted")
    ]
  end

  # Contacts in every verification state; only verified ones are served.
  def contacts
    [
      [ CAND_ALEXIS, "email", "", "pam@example-campaign.ca", "verified" ],
      [ CAND_ALEXIS, "social", "x", "pamalexis", "verified" ],
      [ CAND_ALEXIS, "phone", "", "604-555-0100", "proposed" ],
      [ CAND_ALEXIS, "donate", "", "https://example-campaign.ca/donate", "rejected" ],
      [ CAND_GASPER, "website", "", "https://gasper.example.ca", "proposed" ]
    ].map do |candidacy_id, kind, platform, value, status|
      { candidacy_id:, kind:, platform:, value:, source_url: "https://example-campaign.ca/contact", capture_sha256: ELECTIONS_SHA,
        linked_from_url: nil, evidence_quote: "Contact: #{value}", found_by: "agent:01M3TSCM5FAX2WPSB987S2HWKT", status:, note: nil,
        checked_at: status == "verified" ? T : nil }
    end
  end

  def result_reports
    [ { id: REPORT, election_id: ELECTION, stage: "official", polls_reported: 93, polls_total: 93, published_at: "2024-11-09",
        published_at_as_shown: "November 9, 2024", retrieved_at: T, source_url: "https://elections.bc.ca/2024-provincial-general-election/results/",
        capture_sha256: RESULTS_SHA, content_sha256: sha("report") } ]
  end

  def results
    [
      [ 1, CAND_ALEXIS, "votes", "advance", 1894, nil ], [ 2, CAND_GASPER, "votes", "advance", 2625, nil ],
      [ 3, nil, "rejected", "advance", 12, nil ], [ 4, CAND_ALEXIS, "votes", "mail", nil, "advance" ]
    ].map do |id, candidacy_id, measure, ballot_type, value, reported_under|
      { id:, report_id: REPORT, contest_id: CONTEST_ABM, candidacy_id:, answer: nil, measure:, measure_as_shown: nil, polling_area_id: nil,
        unit_label_as_shown: nil, ballot_type:, ballot_type_as_shown: ballot_type.capitalize, round: 1, value:, reported_under: }
    end
  end
end
