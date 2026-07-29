# Loads Brampton registered candidates into election_races and
# election_candidates from the canonical body built by
# Source::Fetcher::BramptonCandidateList ({year, offices}).
#
# Idempotent: races are keyed by (office, body, district number) and
# candidates by (race, published name), so reruns update in place. Candidates
# who vanish from the page keep their last known row (last_seen_at shows
# staleness); the page marks withdrawals in place rather than in a separate
# feed, so a withdrawn candidate stays visible and stays flagged.
#
# Brampton's districts pair wards: city and regional councillors both run in
# "Wards 1, 5", and the two boards' trustee districts group wards differently
# again. district_number is therefore the district's lowest ward (unique
# within an office_body) with the full list in metadata.ward_numbers, and
# office_body separates the city council seat from the regional one.
#
# The target Warehouse::Election ("brampton-<year>") must already exist — it
# carries the election date and jurisdiction, which are seeded, not scraped
# (db/seeds/elections.rb).
class Warehouse::RawIngestion::BramptonCandidatesLoader < ActiveRecord::AssociatedObject
  performs :load

  # Office-code prefixes from the page's data-office attributes. The trailing
  # digits are the wards the district covers (cc15 = city councillor for wards
  # 1 and 5), which is why prefixes are matched longest-first.
  OFFICES = {
    "mayor" => { office_type: "mayor", district_type: "at_large" },
    "cc" => { office_type: "councillor", district_type: "ward", office_body: "Brampton City Council" },
    "cr" => { office_type: "councillor", district_type: "ward", office_body: "Region of Peel Council" },
    "pdsb" => { office_type: "trustee", district_type: "school_board_ward", office_body: "Peel District School Board" },
    "dpcdsb" => { office_type: "trustee", district_type: "school_board_ward",
                  office_body: "Dufferin-Peel Catholic District School Board" },
    "viamonde" => { office_type: "trustee", district_type: "at_large", office_body: "Conseil scolaire Viamonde" },
    "monavenir" => { office_type: "trustee", district_type: "at_large",
                     office_body: "Conseil scolaire catholique MonAvenir" }
  }.freeze

  PREFIXES = OFFICES.keys.sort_by { |prefix| -prefix.length }.freeze

  def load(json_content:)
    data = JSON.parse(json_content)
    election = Warehouse::Election.find_by!(slug: "brampton-#{data.fetch("year")}")

    counts = { races: 0, candidates: 0, withdrawn: 0, skipped_offices: 0 }

    ActiveRecord::Base.transaction do
      seen_at = Time.current

      Array(data["offices"]).each do |office|
        race = find_race(election, office, counts)
        if race.nil?
          Rails.logger.warn "[BramptonCandidatesLoader] Skipping office with unrecognized " \
            "code #{office["code"].inspect} (#{office["heading"].inspect})"
          counts[:skipped_offices] += 1
          next
        end

        Array(office["candidates"]).each do |candidate|
          upsert_candidate(race, candidate, counts, seen_at)
        end
      end
    end

    raw_ingestion.update!(status: "complete")
    Rails.logger.info "[BramptonCandidatesLoader] #{raw_ingestion.source.name}: #{counts.inspect}"
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end

  private

  def find_race(election, office, counts)
    code = office["code"].to_s
    prefix = PREFIXES.find { |p| code.start_with?(p) }
    return nil if prefix.nil?

    attributes = OFFICES.fetch(prefix)
    # An at-large race covers the whole city, so it carries no district: the
    # page lists every ward for one, but recording that would make
    # ward_numbers mean two different things.
    at_large = attributes[:district_type] == "at_large"
    wards = at_large ? nil : Array(office["wards"]).map { |w| Integer(w) }
    district_number = wards&.min

    race = election.races.find_or_initialize_by(
      office_type: attributes[:office_type],
      office_body: attributes[:office_body],
      district_number: district_number
    )
    counts[:races] += 1 if race.new_record?

    race.update!(
      district_type: attributes[:district_type],
      district_name: district_name(office["heading"]),
      metadata: race.metadata.merge("office_code" => code, "ward_numbers" => wards)
    )
    race
  end

  # Headings read "Councillor, City - Wards 1, 5"; the district is whatever
  # follows the office. At-large headings ("Mayor") have no district part.
  def district_name(heading)
    heading.to_s.split(" - ", 2)[1]&.strip.presence
  end

  def upsert_candidate(race, data, counts, seen_at)
    full_name = data["name"].presence
    if full_name.nil?
      Rails.logger.warn "[BramptonCandidatesLoader] Skipping candidate without a name in #{race.district_name || race.office_type}"
      return nil
    end

    withdrawn = ActiveModel::Type::Boolean.new.cast(data["withdrawn"])
    last, first = full_name.split(",", 2).map { |part| part.strip.presence }

    candidate = race.candidates.find_or_initialize_by(full_name: full_name)
    counts[:candidates] += 1 if candidate.new_record?
    counts[:withdrawn] += 1 if withdrawn

    candidate.update!(
      first_name: first,
      last_name: last,
      status: withdrawn ? "withdrawn" : "active",
      nomination_date: parse_date(data["filing_date"], data["filing_date_text"]),
      email: data["email"].presence,
      phone: data["cell_phone"].presence || data["campaign_phone"].presence,
      website: data["website"].presence,
      social_links: Array(data["socials"]),
      last_seen_at: seen_at
    )
    candidate
  end

  # Filing dates arrive as MMDDYYYY from data-date, with the visible
  # "M/D/YYYY" text as a fallback. The page publishes no withdrawal date.
  def parse_date(packed, text)
    [ [ packed, "%m%d%Y" ], [ text, "%m/%d/%Y" ] ].each do |raw, format|
      next if raw.blank?

      begin
        return Date.strptime(raw.to_s, format)
      rescue ArgumentError
        Rails.logger.warn "[BramptonCandidatesLoader] Unparseable date: #{raw.inspect}"
      end
    end

    nil
  end
end
