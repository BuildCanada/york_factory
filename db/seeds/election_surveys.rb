# Survey definitions for the election tracker.
#
# Question sets are loaded from JSON under db/seeds/elections/. The resident one
# was generated from the tracker's surveyData.ts when the questions moved into
# this app; the Toronto candidate questionnaire was generated from the Google
# Form the candidates actually filled in, so the two share question ids and
# option values wherever they ask the same thing and a candidate's answer can be
# read against the resident tally directly.
#
# The JSON is the migration record, not an ongoing source of truth:
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
  # The resident survey ships live — it is already collecting responses on the
  # site. The candidate questionnaire sets "published": false and is released
  # from the CMS once its imported answers have been reviewed.
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
