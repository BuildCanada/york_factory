# Loads Hamilton certified candidates into election_races and
# election_candidates from the canonical body built by
# Source::Fetcher::HamiltonCandidateList ({year, offices}).
#
# Idempotent: races are keyed by (office, body, district number) and
# candidates by (race, published name), so reruns update in place. Candidates
# who vanish from the page keep their last known row (last_seen_at shows
# staleness).
#
# Hamilton's 15 wards map one-to-one onto councillor races, but trustee
# districts group wards ("Wards 5 & 10 - English Public"), so district_number
# is the district's lowest ward — unique within a board — with the full list in
# metadata.ward_numbers. The page's shorthand board names ("English Public")
# are expanded to the official ones so a board carries the same name here as it
# does in the Toronto and Brampton elections.
#
# The page publishes no nomination dates and no withdrawal list, so
# nomination_date and withdrawn_date stay nil and every candidate is active.
#
# The target Warehouse::Election ("hamilton-<year>") must already exist — it
# carries the election date and jurisdiction, which are seeded, not scraped
# (db/seeds/elections.rb).
class Warehouse::RawIngestion::HamiltonCandidatesLoader < ActiveRecord::AssociatedObject
  performs :load

  # Board names as the page writes them (normalized: downcased, squished),
  # including the "Scolair" typo it has carried since publication.
  BOARDS = {
    "english public" => "Hamilton-Wentworth District School Board",
    "english separate" => "Hamilton-Wentworth Catholic District School Board",
    "conseil scolaire catholique monavenir" => "Conseil scolaire catholique MonAvenir",
    "conseil scolair catholique monavenir" => "Conseil scolaire catholique MonAvenir",
    "conseil scolaire viamonde" => "Conseil scolaire Viamonde"
  }.freeze

  def load(json_content:)
    data = JSON.parse(json_content)
    election = Warehouse::Election.find_by!(slug: "hamilton-#{data.fetch("year")}")

    counts = { races: 0, candidates: 0, skipped_offices: 0 }

    ActiveRecord::Base.transaction do
      seen_at = Time.current

      Array(data["offices"]).each do |office|
        race = find_race(election, office, counts)
        if race.nil?
          Rails.logger.warn "[HamiltonCandidatesLoader] Skipping office " \
            "#{office["section"].inspect} / #{office["label"].inspect}"
          counts[:skipped_offices] += 1
          next
        end

        Array(office["candidates"]).each { |candidate| upsert_candidate(race, candidate, counts, seen_at) }
      end
    end

    raw_ingestion.update!(status: "complete")
    Rails.logger.info "[HamiltonCandidatesLoader] #{raw_ingestion.source.name}: #{counts.inspect}"
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end

  private

  def find_race(election, office, counts)
    attributes = race_attributes(office)
    return nil if attributes.nil?

    race = election.races.find_or_initialize_by(
      office_type: attributes[:office_type],
      office_body: attributes[:office_body],
      district_number: attributes[:district_number]
    )
    counts[:races] += 1 if race.new_record?

    race.update!(
      district_type: attributes[:district_type],
      district_name: district_name(attributes[:ward_numbers]),
      metadata: race.metadata.merge("ward_numbers" => attributes[:ward_numbers])
    )
    race
  end

  # Returns nil for anything unplaceable — an unknown section, a councillor
  # district with no ward number, or a school board we don't recognize — so the
  # rest of the page still loads and the gap shows up in the logs and counts.
  def race_attributes(office)
    wards = ward_numbers(district_part(office["label"]))

    case office["section"]
    when "mayor"
      # An at-large race covers the whole city, so it carries no district and
      # no ward list.
      { office_type: "mayor", district_type: "at_large", district_number: nil, ward_numbers: nil }
    when "councillor"
      return nil if wards.empty?

      { office_type: "councillor", district_type: "ward", district_number: wards.min, ward_numbers: wards }
    when "trustee"
      board = BOARDS[normalize(board_part(office["label"]))]
      return nil if board.nil?

      # The French-language boards elect one trustee across the whole city.
      return { office_type: "trustee", office_body: board, district_type: "at_large",
               district_number: nil, ward_numbers: nil } if wards.empty?

      { office_type: "trustee", office_body: board, district_type: "school_board_ward",
        district_number: wards.min, ward_numbers: wards }
    end
  end

  # Trustee labels read "Wards 5 & 10 - English Public"; the district is
  # everything before the board. Councillor labels ("Ward 1") are all district,
  # and the French boards' labels are all board.
  def district_part(label)
    parts = label.to_s.split(" - ", 2)
    parts.length > 1 ? parts.first : label.to_s
  end

  def board_part(label)
    parts = label.to_s.split(" - ", 2)
    parts.length > 1 ? parts.last : label.to_s
  end

  def ward_numbers(text)
    text.to_s.scan(/\d+/).map(&:to_i).uniq.sort
  end

  # Derived rather than taken from the page so the label reads the same way for
  # every district, whatever punctuation the page used ("Wards 5 & 10").
  def district_name(wards)
    return nil if wards.blank?

    wards.one? ? "Ward #{wards.first}" : "Wards #{wards.join(", ")}"
  end

  def normalize(value)
    value.to_s.gsub(/[[:space:]]+/, " ").strip.downcase
  end

  def upsert_candidate(race, data, counts, seen_at)
    full_name = data["name"].presence
    if full_name.nil?
      Rails.logger.warn "[HamiltonCandidatesLoader] Skipping candidate without a name in #{race.district_name || race.office_type}"
      return nil
    end

    last, first = full_name.split(",", 2).map { |part| part.strip.presence }

    candidate = race.candidates.find_or_initialize_by(full_name: full_name)
    counts[:candidates] += 1 if candidate.new_record?

    candidate.update!(
      first_name: first,
      last_name: last,
      status: "active",
      email: data["email"].presence,
      phone: data["phone"].presence,
      last_seen_at: seen_at
    )
    candidate
  end
end
