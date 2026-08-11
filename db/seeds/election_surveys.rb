# Survey definitions for the election tracker.
#
# Resident question sets are loaded from JSON under db/seeds/elections/, which
# was generated from the tracker's surveyData.ts when the questions moved into
# this app. The JSON is the migration record, not an ongoing source of truth:
# after this runs, the database is authoritative and questions are edited in the
# CMS. Re-running is safe and will overwrite CMS edits to the questions it
# names, so treat it as a restore, not a sync.
#
# Idempotent by (election, survey slug) and (survey, question_id).

def load_election_survey(path)
  definition = JSON.parse(File.read(path))
  election = Warehouse::Election.find_by!(slug: definition.fetch("election_slug"))

  survey = Warehouse::ElectionSurvey.find_or_initialize_by(
    election: election,
    slug: definition.fetch("slug")
  )
  survey.audience = definition.fetch("audience")
  survey.version = definition.fetch("version")
  survey.meta = definition.fetch("meta", {})
  # Resident surveys ship live — this one is already collecting responses on the
  # site. A candidate questionnaire is authored in the CMS and published there.
  survey.published_at ||= Time.current if definition.fetch("published", true)
  survey.save!

  definition.fetch("questions").each do |attrs|
    question = survey.questions.find_or_initialize_by(
      question_id: attrs.fetch("question_id")
    )
    question.assign_attributes(attrs.except("question_id"))
    question.save!
  end

  # Questions dropped from the definition are removed, so a re-run converges on
  # the file rather than leaving orphans behind.
  keep = definition.fetch("questions").map { |q| q.fetch("question_id") }
  removed = survey.questions.where.not(question_id: keep)
  puts "  removing #{removed.count} question(s) no longer in the definition" if removed.any?
  removed.destroy_all

  puts "Seeded survey #{election.slug}/#{survey.slug} " \
       "(#{survey.audience}, v#{survey.version}, #{survey.questions.count} questions)"
  survey
end

Dir[Rails.root.join("db/seeds/elections/*.json")].sort.each do |path|
  load_election_survey(path)
end

# The candidate questionnaire for Toronto 2026. Created empty and unpublished on
# purpose: the questions are still being written, and the public API skips
# unpublished surveys, so this can sit in the CMS until it is ready without
# appearing on the site.
toronto = Warehouse::Election.find_by(slug: "toronto-2026")
if toronto
  questionnaire = Warehouse::ElectionSurvey.find_or_initialize_by(
    election: toronto,
    slug: "candidate-questionnaire"
  )
  if questionnaire.new_record?
    questionnaire.audience = "candidate"
    questionnaire.version = "1"
    questionnaire.meta = {
      "title" => "Toronto 2026 candidate questionnaire",
      "intro" => "What each candidate told us they would do in office."
    }
    questionnaire.save!
    puts "Created empty candidate questionnaire for toronto-2026 (unpublished — " \
         "add questions in admin, then publish)"
  end
end
