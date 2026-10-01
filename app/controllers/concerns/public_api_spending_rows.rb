# Serializing a page of spending rows the same way on every /v1 operation
# that returns them: the parties are loaded and shown only when asked, and
# caveats follow the rows' sources and the slices the revision reads.
module PublicApiSpendingRows
  extend ActiveSupport::Concern

  private

  def spending_query = @spending_query ||= FactFactory::SpendingQuery.new(revision:)

  def expand?(name) = Array(parameters["expand"]).include?(name)

  def serialize_records(records, show_parties:)
    parties = show_parties ? spending_query.parties(records) : {}
    latest = spending_query.latest_revisions(records)
    entities = show_parties ? entity_query.refs(parties.values.flatten.filter_map(&:entity_id)) : {}
    records.map do |r|
      row_parties = spending_query.parties_for(parties, r) if show_parties
      item = PublicApi::V1::SpendingSerializer.record(r, context, parties: row_parties, latest: latest.fetch(r.spending_key, true),
        publication: spending_query.slices.publication(r.publication_id), entities:, raw: expand?("raw"))
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
    caveats.concat(slice_caveats)
    records.map(&:source_key).uniq.each { |s| caveats.concat(source_caveats(s)) }
    caveats
  end

  # The spending slices the revision can't read (resolved before spending moved
  # to PostgreSQL), named so a reader knows the rows are incomplete.
  def slice_caveats
    unreadable = spending_query.slices.unreadable
    return [] if unreadable.empty?

    detail = if locale == "fr"
      "Certaines tranches de dépenses ne sont pas lisibles à cette révision : #{unreadable.keys.sort.join(', ')}."
    else
      "Some spending slices can't be read as of this revision, so their rows are missing: #{unreadable.keys.sort.join(', ')}."
    end
    [ PublicApi::Catalog.caveat(:coverage_partial, locale:, detail:) ]
  end

  def source_caveats(source_key)
    source = PublicApi::Catalog.source(source_key) or return []
    (source.caveats - [ "not_cross_source_total" ]).map { |code| PublicApi::Catalog.caveat(code, locale:) }
  end
end
