# Loads Toronto registered candidates into election_races and
# election_candidates from the canonical body built by
# Source::Fetcher::TorontoCandidateList ({year, mayor, councillor, trustee,
# withdrawn}).
#
# Idempotent: races are keyed by (office, board, district number) and
# candidates by (race, published name), so reruns update in place. Candidates
# in the withdrawn feed are marked withdrawn even after the City drops them
# from the active lists; candidates who vanish from every feed keep their
# last known row (last_seen_at shows staleness).
#
# The target Warehouse::Election ("toronto-<year>") must already exist —
# it carries the election date and jurisdiction, which are seeded, not
# scraped (db/seeds/elections.rb).
class Warehouse::RawIngestion::TorontoCandidatesLoader < ActiveRecord::AssociatedObject
  performs :load

  # Toronto's 25-ward model (Dec 2018). The feed's own ward names are
  # placeholders ("Name:1"), so real names live here; they also exist as
  # ward_toronto geo boundaries, but a static map keeps the loader
  # self-contained.
  CITY_WARD_NAMES = {
    1 => "Etobicoke North", 2 => "Etobicoke Centre", 3 => "Etobicoke-Lakeshore",
    4 => "Parkdale-High Park", 5 => "York South-Weston", 6 => "York Centre",
    7 => "Humber River-Black Creek", 8 => "Eglinton-Lawrence", 9 => "Davenport",
    10 => "Spadina-Fort York", 11 => "University-Rosedale", 12 => "Toronto-St. Paul's",
    13 => "Toronto Centre", 14 => "Toronto-Danforth", 15 => "Don Valley West",
    16 => "Don Valley East", 17 => "Don Valley North", 18 => "Willowdale",
    19 => "Beaches-East York", 20 => "Scarborough Southwest", 21 => "Scarborough Centre",
    22 => "Scarborough-Agincourt", 23 => "Scarborough North", 24 => "Scarborough-Guildwood",
    25 => "Scarborough-Rouge Park"
  }.freeze

  # Office codes from the City's electionDictionary.json: 1 mayor,
  # 2 councillor, 3-6 the four school boards (trustee races).
  SCHOOL_BOARDS = {
    3 => "Toronto District School Board",
    4 => "Toronto Catholic District School Board",
    5 => "Conseil scolaire Viamonde",
    6 => "Conseil scolaire catholique MonAvenir"
  }.freeze

  def load(json_content:)
    data = JSON.parse(json_content)
    election = Warehouse::Election.find_by!(slug: "toronto-#{data.fetch("year")}")

    counts = { races: 0, candidates: 0, withdrawn: 0 }
    seen_at = Time.current

    ActiveRecord::Base.transaction do
      mayor_race = find_race(election, counts, office_type: "mayor", district_type: "at_large")
      Array(data["mayor"]).each { |c| upsert_candidate(mayor_race, c, counts, seen_at) }

      Array(data["councillor"]).each do |ward|
        number = Integer(ward.fetch("num"))
        race = find_race(election, counts, office_type: "councillor", district_type: "ward",
          district_number: number, district_name: CITY_WARD_NAMES[number])
        Array(ward["candidate"]).each { |c| upsert_candidate(race, c, counts, seen_at) }
      end

      Array(data["trustee"]).each do |board|
        board_name = SCHOOL_BOARDS.fetch(board.fetch("id")) { |id| "School board #{id}" }
        Array(board["ward"]).each do |ward|
          race = find_race(election, counts, office_type: "trustee", district_type: "school_board_ward",
            office_body: board_name, district_number: Integer(ward.fetch("num")))
          Array(ward["candidate"]).each { |c| upsert_candidate(race, c, counts, seen_at) }
        end
      end

      Array(data["withdrawn"]).each do |candidate|
        race = withdrawn_race(election, counts, candidate)
        if race.nil?
          Rails.logger.warn "[TorontoCandidatesLoader] Skipping withdrawn candidate with " \
            "unknown office #{candidate["office"].inspect}: #{candidate["name"]}"
          next
        end
        upsert_candidate(race, candidate, counts, seen_at)
        counts[:withdrawn] += 1
      end
    end

    raw_ingestion.update!(status: "complete")
    Rails.logger.info "[TorontoCandidatesLoader] #{raw_ingestion.source.name}: #{counts.inspect}"
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end

  private

  def find_race(election, counts, office_type:, district_type:, district_number: nil, district_name: nil, office_body: nil)
    race = election.races.create_with(district_name: district_name)
      .find_or_create_by!(office_type: office_type, district_type: district_type,
        district_number: district_number, office_body: office_body)
    counts[:races] += 1 if race.previously_new_record?
    race
  end

  # Withdrawn-feed entries carry only office code + ward, so the race is
  # reconstructed the same way the active feeds build theirs (and created if
  # every active candidate in it has already withdrawn).
  def withdrawn_race(election, counts, candidate)
    case candidate["office"]
    when 1
      find_race(election, counts, office_type: "mayor", district_type: "at_large")
    when 2
      number = Integer(candidate.fetch("ward"))
      find_race(election, counts, office_type: "councillor", district_type: "ward",
        district_number: number, district_name: CITY_WARD_NAMES[number])
    when *SCHOOL_BOARDS.keys
      find_race(election, counts, office_type: "trustee", district_type: "school_board_ward",
        office_body: SCHOOL_BOARDS.fetch(candidate["office"]), district_number: Integer(candidate.fetch("ward")))
    end
  end

  def upsert_candidate(race, data, counts, seen_at)
    socials = Array(data["socialMedias"])

    candidate = race.candidates.find_or_initialize_by(full_name: data.fetch("name"))
    counts[:candidates] += 1 if candidate.new_record?
    candidate.update!(
      first_name: data["firstName"],
      last_name: data["lastName"],
      status: data["status"].to_s.casecmp?("withdrawn") ? "withdrawn" : "active",
      nomination_date: parse_date(data["dateNomination"]),
      withdrawn_date: parse_date(data["dateWithdrawn"]),
      email: data["email"].presence,
      phone: data["phone"].presence,
      website: socials.find { |s| s["name"] == "web" }&.dig("url").presence,
      social_links: socials,
      last_seen_at: seen_at
    )
    candidate
  end

  # Feed dates look like "19-May-2026".
  def parse_date(raw)
    return nil if raw.blank?

    Date.strptime(raw, "%d-%b-%Y")
  rescue ArgumentError
    Rails.logger.warn "[TorontoCandidatesLoader] Unparseable date: #{raw.inspect}"
    nil
  end
end
