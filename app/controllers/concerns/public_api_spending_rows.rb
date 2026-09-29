# Serializing a page of spending rows the same way on every /v1 operation
# that returns them: the parties are always loaded (the postal code rule reads
# them) but shown only when asked, and caveats follow the rows' sources.
module PublicApiSpendingRows
  extend ActiveSupport::Concern

  private

  def spending_query = @spending_query ||= FactFactory::SpendingQuery.new(release:)

  def expand?(name) = Array(parameters["expand"]).include?(name)

  def serialize_records(records, show_parties:)
    parties = spending_query.parties(records)
    latest = spending_query.latest_revisions(records)
    linked = parties.values.flatten.filter_map(&:entity_id)
    entities = show_parties ? entity_query.refs(linked) : {}
    records.map do |r|
      row_parties = parties.fetch([ r.asset_key, r.acquisition, r.source_row_id ], [])
      item = PublicApi::V1::SpendingSerializer.record(r, context, parties: row_parties, latest: latest.fetch(r.spending_key, true),
        entities:, show_parties:, raw: expand?("raw"))
      project(item)
    end
  end

  def spending_cursor_key(record, sort)
    case sort
    when "amount", "-amount" then [ record.amount && PublicApi::Format.amount(record.amount), record.spending_key ]
    when "date", "-date" then [ record.date&.iso8601, record.spending_key ]
    else [ record.spending_key ]
    end
  end

  def record_caveats(records, filters)
    caveats = []
    caveats << PublicApi::Catalog.caveat(:revisions_listed, locale:) unless filters["latest_revision_only"]
    caveats << PublicApi::Catalog.caveat(:archive_overlaps_live, locale:) if records.any? { |r| r.acquisition == "archive_import" }
    caveats << PublicApi::Catalog.caveat(:raw_unavailable, locale:) if expand?("raw")
    records.map(&:source_key).uniq.each { |s| caveats.concat(source_caveats(s)) }
    caveats
  end

  def source_caveats(source_key)
    source = PublicApi::Catalog.source(source_key) or return []
    (source.caveats - [ "not_cross_source_total" ]).map { |code| PublicApi::Catalog.caveat(code, locale:) }
  end
end
