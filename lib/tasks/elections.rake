# Imports a candidate questionnaire from the Google Form CSV the candidates
# filled in.
#
# There is no fetcher for this: the form is a Google Sheet a human exports, not
# an addressable source, so it does not belong in the Source/RawIngestion
# pipeline. It is a rake task taking a path, run once per export.
#
# Usage:
#   bin/rails "elections:import_candidate_questionnaire[/path/to/export.csv]"
#   DRY_RUN=1 bin/rails "elections:import_candidate_questionnaire[...]"   # report only
#
# Responses land as `draft` with source `form`, never published — a candidate's
# answers are attributed public statements, so releasing them is a decision made
# in the CMS after review, not a side effect of an import.
namespace :elections do
  # Google Form column indexes for the Toronto 2026 export. Hard-coded rather
  # than matched on header text because the headers carry question numbers that
  # were renumbered mid-collection: question 21 was added after 34 and sits at
  # column 63, and column 19 is an unnumbered earlier draft of the autonomous
  # taxi question that only one candidate ever saw. Matching on prose would
  # silently mismap both.
  #
  # Verified against the header row on load — see CandidateQuestionnaireImport.
  ANSWER_COLUMNS = {
    "bio" => 3,
    "housing_as_of_right" => 4,
    "encampment_removal" => 6,
    "road_pricing" => 8,
    "infrastructure_revenue" => 10,
    "capital_transparency" => 12,
    "housing_intervention" => 14,
    "housing_city_role" => 15,
    "housing_density_location" => 16,
    "transit_funding_priority" => 17,
    "street_space_priority" => 18,
    "av_regulation_priority" => 19,
    "safety_investment" => 20,
    "police_budget" => 21,
    "surveillance_tech" => 22,
    "housing_cost_reduction" => 23,
    "capital_project_delays" => 24,
    "service_delivery_model" => 25,
    "property_tax_growth" => 26,
    "revenue_source" => 27,
    "infrastructure_backlog" => 28,
    "provincial_approach" => 29,
    "strong_mayor_powers" => 63,
    "ward_objective" => 30,
    "performance_metric" => 31,
    "ward_commitment_target" => 32,
    "cycling_network" => 33,
    "protest_access" => 34,
    "technology_investment" => 35,
    "budget_gap_first" => 36,
    "business_climate" => 37,
    "business_attraction" => 38,
    "construction_capacity" => 39,
    "public_realm_priority" => 40,
    "arts_culture_support" => 41,
    "av_conditions" => 42
  }.freeze

  # The per-question "N. Comments (300 characters max.)" columns, which become
  # `explanations`. Question 21's late insertion shifts everything from 21 on by
  # one, which is why this is a formula rather than a range.
  COMMENT_COLUMNS = {
    "housing_as_of_right" => 43,
    "encampment_removal" => 44,
    "road_pricing" => 45,
    "infrastructure_revenue" => 46,
    "capital_transparency" => 47,
    "housing_intervention" => 48,
    "housing_city_role" => 49,
    "housing_density_location" => 50,
    "transit_funding_priority" => 51,
    "street_space_priority" => 52,
    "safety_investment" => 53,
    "police_budget" => 54,
    "surveillance_tech" => 55,
    "housing_cost_reduction" => 56,
    "capital_project_delays" => 57,
    "service_delivery_model" => 58,
    "property_tax_growth" => 59,
    "revenue_source" => 60,
    "infrastructure_backlog" => 61,
    "provincial_approach" => 62,
    "strong_mayor_powers" => 64,
    "ward_objective" => 65,
    "performance_metric" => 66,
    "ward_commitment_target" => 67,
    "cycling_network" => 68,
    "protest_access" => 69,
    "technology_investment" => 70,
    "budget_gap_first" => 71,
    "business_climate" => 72,
    "business_attraction" => 73,
    "construction_capacity" => 74,
    "public_realm_priority" => 75,
    "arts_culture_support" => 76,
    "av_conditions" => 77
  }.freeze

  # A second comment box on question 1 from an earlier revision of the form.
  # Folded into that question's explanation when the current box is empty, so
  # the one candidate who used it is not dropped.
  LEGACY_Q1_COMMENT_COLUMN = 5

  NAME_COLUMN = 2
  EMAIL_COLUMN = 1
  TIMESTAMP_COLUMN = 0

  # Candidates the form and the roster spell far enough apart that no matching
  # rule should bridge them — a nickname the roster does not carry, filed under
  # a campaign address the candidate did not use on the form.
  #
  # Keyed on the address typed into the form, mapping to the roster's address.
  # A wrong entry here attributes one candidate's public positions to another,
  # so add a row only after confirming the office and campaign match by hand.
  MANUAL_CANDIDATE_ALIASES = {
    # "Josh Thompson" <urfavoritejosh@gmail.com>, running for mayor at
    # joshthompsonformayor.ca, is "Thompson, Joshua" in the Toronto feed.
    "urfavoritejosh@gmail.com" => "votejoshthompson2026@pm.me"
  }.freeze

  # Header text each mapped column must start with, as a guard that the export
  # has not been re-ordered under us. Deliberately a prefix and only on the
  # columns whose position is surprising.
  COLUMN_ASSERTIONS = {
    0 => "Timestamp",
    1 => "Email Address",
    2 => "Full name",
    3 => "Bio",
    5 => "Comments",
    19 => "If large-scale autonomous taxi",
    43 => "1. Comments",
    62 => "20. Comments",
    63 => "21. Strong mayor powers",
    64 => "21. Comments",
    77 => "34. Comments"
  }.freeze

  desc "Import candidate questionnaire answers from a Google Form CSV export"
  task :import_candidate_questionnaire, [ :path ] => :environment do |_t, args|
    path = args[:path].presence || abort("Usage: bin/rails \"elections:import_candidate_questionnaire[path/to.csv]\"")
    abort "No such file: #{path}" unless File.exist?(path)

    import = CandidateQuestionnaireImport.new(
      path: path,
      election_slug: ENV.fetch("ELECTION_SLUG", "toronto-2026"),
      survey_slug: ENV.fetch("SURVEY_SLUG", "candidate-questionnaire"),
      entered_by: ENV["ENTERED_BY"].presence || "elections:import_candidate_questionnaire",
      dry_run: ENV["DRY_RUN"].present?
    )
    import.run
  end

  # Reads one export and upserts a draft response per candidate it can identify.
  #
  # Re-runnable by design. Rows whose candidate is not on the roster yet are
  # skipped and reported rather than failing the import — the roster is fed by
  # the Toronto candidate pipeline and lags the form — so the fix for a skipped
  # row is to refresh the roster and run this again.
  class CandidateQuestionnaireImport
    Result = Struct.new(:imported, :updated, :skipped, :unmatched, :unmapped, keyword_init: true)

    def initialize(path:, election_slug:, survey_slug:, entered_by:, dry_run: false)
      @path = path
      @election_slug = election_slug
      @survey_slug = survey_slug
      @entered_by = entered_by
      @dry_run = dry_run
    end

    def run
      require "csv"
      rows = CSV.read(@path, headers: false, encoding: "bom|utf-8", row_sep: row_separator)
      header = rows.shift
      assert_columns!(header)

      survey = load_survey
      known_question_ids = survey.questions.map(&:question_id).to_set
      unknown = (ANSWER_COLUMNS.keys + COMMENT_COLUMNS.keys).uniq - known_question_ids.to_a
      if unknown.any?
        abort "The survey is missing questions this import writes to: #{unknown.sort.join(', ')}. " \
              "Run bin/rails db:seed to load db/seeds/elections/*.json first."
      end

      candidates = CandidateIndex.new(survey.election)
      @options = OptionMapper.new(survey)
      result = Result.new(imported: 0, updated: 0, skipped: [], unmatched: [], unmapped: [])

      ActiveRecord::Base.transaction do
        rows.each_with_index do |row, offset|
          import_row(row, line: offset + 2, survey: survey, candidates: candidates, result: result)
        end
        raise ActiveRecord::Rollback if @dry_run
      end

      report(result, survey: survey)
    end

    private

    # Google separates rows with CRLF but leaves a bare LF inside any answer a
    # candidate typed on more than one line — and there are plenty of those.
    # CSV's auto-detection sees the first bare LF, which is inside a quoted
    # header cell, decides that is the row separator, and then fails on the
    # first real row break. So the separator is read off the file instead.
    def row_separator
      File.binread(@path, 64 * 1024).include?("\r\n") ? "\r\n" : "\n"
    end

    def load_survey
      election = Warehouse::Election.find_by(slug: @election_slug)
      abort "No election #{@election_slug}" if election.nil?
      survey = election.surveys.find_by(slug: @survey_slug)
      abort "No survey #{@election_slug}/#{@survey_slug}" if survey.nil?
      abort "#{@survey_slug} is not a candidate survey" unless survey.candidate?
      survey
    end

    # A re-ordered export would map answers onto the wrong questions and publish
    # candidates saying things they did not say, so this stops rather than
    # guesses.
    def assert_columns!(header)
      COLUMN_ASSERTIONS.each do |index, prefix|
        actual = header[index].to_s.strip
        next if actual.start_with?(prefix)

        abort "Column #{index} should start with #{prefix.inspect} but reads #{actual.inspect}. " \
              "The export's columns have moved — recheck ANSWER_COLUMNS before importing."
      end
    end

    def import_row(row, line:, survey:, candidates:, result:)
      name = row[NAME_COLUMN].to_s.strip
      email = row[EMAIL_COLUMN].to_s.strip

      if test_submission?(name, email)
        result.skipped << "line #{line}: #{name} <#{email}> — test submission"
        return
      end

      candidate = candidates.find(name: name, email: email)
      if candidate.nil?
        result.unmatched << "line #{line}: #{name} <#{email}>"
        return
      end

      answers = extract(row, ANSWER_COLUMNS).to_h do |question_id, text|
        value = @options.value_for(question_id, text)
        if value.nil?
          result.unmapped << "line #{line}: #{question_id} = #{text.truncate(60).inspect}"
        end
        [ question_id, value || text ]
      end
      explanations = extract(row, COMMENT_COLUMNS)
      legacy = row[LEGACY_Q1_COMMENT_COLUMN].to_s.strip
      explanations["housing_as_of_right"] ||= legacy if legacy.present?

      if answers.empty?
        result.skipped << "line #{line}: #{name} — no answers"
        return
      end

      response = Warehouse::ElectionCandidateSurveyResponse.find_or_initialize_by(
        survey: survey, candidate: candidate
      )
      was_new = response.new_record?

      # `status` and `published_at` are left alone on an existing row: a staff
      # member may have already reviewed and published this candidate, and a
      # re-import is not a reason to undo that. Only the answers are refreshed.
      response.assign_attributes(
        answers: answers,
        explanations: explanations,
        survey_version: survey.version,
        source: "form",
        entered_by: @entered_by,
        submitted_at: parse_timestamp(row[TIMESTAMP_COLUMN])
      )
      response.status ||= "draft"

      if response.save
        was_new ? result.imported += 1 : result.updated += 1
      else
        result.skipped << "line #{line}: #{name} — #{response.errors.full_messages.join('; ')}"
      end
    end

    # Blank cells are omitted rather than stored as "", so
    # #unanswered_question_ids reports a genuinely unanswered question and the
    # tallies do not gain an empty bucket.
    def extract(row, columns)
      columns.each_with_object({}) do |(question_id, index), out|
        value = row[index].to_s.strip
        out[question_id] = value if value.present?
      end
    end

    # Google writes the form's timestamp in US M/D/YYYY, which Time.zone.parse
    # reads as D/M/YYYY: "9/5/2026" quietly became 5 September, and every row
    # dated past the 12th of a month raised and fell back to the import's own
    # clock — so a re-run kept restamping half the responses as submitted now.
    # The export's own format is tried first, and a generic parse only after.
    def parse_timestamp(raw)
      value = raw.to_s.strip
      return Time.current if value.blank?

      strptime(value, "%m/%d/%Y %H:%M:%S") || loose_parse(value) || Time.current
    end

    def strptime(value, format)
      Time.zone.strptime(value, format)
    rescue ArgumentError
      nil
    end

    def loose_parse(value)
      Time.zone.parse(value)
    rescue ArgumentError
      nil
    end

    # The form is a public link, so it collected the team's own test rows.
    def test_submission?(name, email)
      email.end_with?("@test.com") || name.match?(/\btest\b/i)
    end

    def report(result, survey:)
      puts "#{@dry_run ? '[DRY RUN] ' : ''}#{@election_slug}/#{@survey_slug}: " \
           "#{result.imported} imported, #{result.updated} updated"

      if result.skipped.any?
        puts "\nSkipped (#{result.skipped.size}):"
        result.skipped.each { |line| puts "  #{line}" }
      end

      if result.unmatched.any?
        puts "\nNot on the #{@election_slug} roster (#{result.unmatched.size}) — refresh the " \
             "candidate roster and re-run to pick these up:"
        result.unmatched.each { |line| puts "  #{line}" }
      end

      if result.unmapped.any?
        puts "\nStored as prose, no matching option (#{result.unmapped.size}) — these will not " \
             "group in a tally until the question's options cover them:"
        result.unmapped.each { |line| puts "  #{line}" }
      end

      return if @dry_run

      stored = survey.candidate_responses.count
      answered = survey.candidate_responses.sum { |r| r.answers.size }
      by_status = survey.candidate_responses.group(:status).count
      drafts = by_status.fetch("draft", 0)
      puts "\n#{stored} response(s) on file, #{answered} answers total " \
           "(#{by_status.sort.map { |status, n| "#{n} #{status}" }.join(', ')})."
      puts "#{drafts} awaiting review — publish from the CMS." if drafts.positive?
    end
  end

  # Turns the prose a Google Form records into the option value the question
  # stores.
  #
  # The form writes out the whole choice — "Public delivery: Build or finance
  # substantially more affordable and supportive housing" — while the question
  # holds that as a value ("public_delivery") plus a label and detail. Storing
  # the prose would work for display and break every tally, since the resident
  # answer to the same question is the short value.
  #
  # A free-text question has no options and never maps; the caller keeps the raw
  # text. So does a choice the question doesn't offer, which is reported rather
  # than dropped — the model deliberately allows an answer that isn't one of the
  # options, and losing what a candidate said would be worse than an untallied
  # row.
  class OptionMapper
    def initialize(survey)
      @by_question = survey.questions.to_h do |question|
        lookup = {}
        question.options_for.each do |option|
          label = option["label"].to_s
          detail = option["detail"].to_s
          lookup[key(detail.present? ? "#{label}: #{detail}" : label)] = option["value"]
          # Also on the label alone, so an option whose detail is edited in the
          # CMS after this import still matches on a re-run.
          lookup[key(label)] ||= option["value"]
        end
        [ question.question_id, lookup ]
      end
    end

    def value_for(question_id, text)
      lookup = @by_question[question_id]
      return text if lookup.blank? # free text — already what we want to store

      lookup[key(text)]
    end

    private

    # Em dashes, curly quotes and stray whitespace all differ between the form
    # and the question set; none of them should decide whether an answer counts.
    def key(value)
      value.to_s
        .unicode_normalize(:nfkc)
        .tr("‘’“”", "''\"\"")
        .gsub(/[^[:alnum:]]+/, " ")
        .downcase
        .strip
    end
  end

  # Resolves a form-typed name to a roster candidate.
  #
  # The roster stores "Last, First" from the Toronto feed while candidates type
  # "First Last" in whatever case they like, sometimes with a middle name and
  # sometimes with an accent the feed spells differently, so matching runs from
  # strictest to loosest and stops at the first hit. First-plus-last is the
  # loosest rung deliberately: dropping a middle name is common and safe, while
  # matching on a surname alone would attribute positions to the wrong person in
  # a race with two Smiths.
  class CandidateIndex
    def initialize(election)
      @by_email = {}
      @by_full = {}
      @by_first_last = {}

      candidates(election).each do |candidate|
        email = candidate.email.to_s.downcase.strip
        @by_email[email] ||= candidate if email.present?

        variants(candidate).each { |name| @by_full[normalize(name)] ||= candidate }

        first = candidate.first_name.to_s
        last = candidate.last_name.to_s
        if first.present? && last.present?
          @by_first_last[normalize("#{first} #{last}")] ||= candidate
        end
      end
    end

    def find(name:, email:)
      address = email.to_s.downcase.strip
      address = MANUAL_CANDIDATE_ALIASES.fetch(address, address)

      by_email = @by_email[address]
      return by_email if by_email

      normalized = normalize(name)
      return @by_full[normalized] if @by_full.key?(normalized)

      tokens = normalized.split
      return nil if tokens.size < 2

      @by_first_last[[ tokens.first, tokens.last ].join(" ")]
    end

    private

    def candidates(election)
      Warehouse::ElectionCandidate
        .where(election_race_id: election.races.select(:id))
        .includes(:race)
    end

    # "Hoàng-Lefranc, Andi" also has to match "Andi Hoàng-Lefranc".
    def variants(candidate)
      full = candidate.full_name.to_s
      [ full, full.split(",").map(&:strip).reverse.join(" ") ]
    end

    # Accents folded, punctuation flattened to spaces: "Hoàng-Lefranc" and
    # "Hoang Lefranc" are the same person spelled two ways by two sources.
    def normalize(value)
      value.to_s
        .unicode_normalize(:nfkd)
        .gsub(/\p{Mn}/, "")
        .downcase
        .gsub(/[^a-z ]/, " ")
        .squeeze(" ")
        .strip
    end
  end
end
