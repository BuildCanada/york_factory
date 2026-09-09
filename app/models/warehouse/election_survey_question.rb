# One question in an election survey, carrying its step so the tracker can
# render the survey in pages without a separate steps table.
#
# `question_id` is the payload key answers are stored under, in both
# warehouse.election_survey_responses and
# warehouse.election_candidate_survey_responses. Changing it after responses
# exist orphans every answer already collected, which is why it is locked once
# the survey is published (see #question_id_is_stable).
class Warehouse::ElectionSurveyQuestion < Warehouse::Record
  self.table_name = "warehouse.election_survey_questions"

  # Mirrors the renderer's union type in the tracker (SurveyQuestion). Adding a
  # type here means teaching SurveyClient to render it, so the CHECK constraint
  # and this list are intentionally narrow.
  TYPES = %w[text email textarea select radio yesno].freeze

  # Types whose answer is chosen from `options`, and so must have some.
  CHOICE_TYPES = %w[select radio].freeze

  # `options_source` values. Each defers to the election at serve time so the
  # list tracks what the election actually holds instead of a frozen copy:
  # "wards" reads the council wards, "mayoral_candidates" the people on the
  # mayoral ballot — a roster the candidate scrapers keep changing right up to
  # nomination day.
  OPTIONS_SOURCES = %w[wards mayoral_candidates].freeze

  # Appended to every sourced list. A sourced question is required and its list
  # is not exhaustive of what a resident might think — someone who doesn't know
  # their ward, or hasn't decided who to vote for, needs an answer that isn't a
  # guess.
  UNSURE_LABELS = {
    "wards" => "I'm not sure",
    "mayoral_candidates" => "Not sure"
  }.freeze

  # A yes/no question renders as a fixed two-up pair, so its options are implied
  # rather than stored. Kept here so the values the tracker submits and the
  # values published results group by have one definition.
  YES_NO = [
    { "value" => "yes", "label" => "Yes" },
    { "value" => "no", "label" => "No" }
  ].freeze

  belongs_to :survey,
    class_name: "Warehouse::ElectionSurvey",
    foreign_key: :election_survey_id,
    inverse_of: :questions

  validates :question_id, presence: true,
    format: { with: /\A[a-z0-9_]{1,64}\z/, message: "must be lowercase, digits and underscores" },
    uniqueness: { scope: :election_survey_id }
  validates :step_id, presence: true, length: { maximum: 100 }
  validates :step_title, presence: true
  validates :label, presence: true
  validates :question_type, presence: true, inclusion: { in: TYPES }
  validates :options_source, inclusion: { in: OPTIONS_SOURCES }, allow_nil: true
  validate :options_are_well_formed
  validate :choice_questions_have_options
  validate :question_id_is_stable

  scope :ordered, -> { order(:step_position, :position, :id) }

  # The question in the shape the tracker's renderer expects, with only the keys
  # it uses — a null help or placeholder is omitted rather than sent, so the
  # payload reads the same as the hand-written definition it replaces.
  def as_definition(option_sources: {})
    {
      id: question_id,
      type: question_type,
      label: label,
      context: context.presence,
      help: help.presence,
      topic: topic.presence,
      placeholder: placeholder.presence,
      required: required.presence,
      rows: rows,
      options: options_for(option_sources: option_sources).presence
    }.compact
  end

  # The choices for this question. Literal `options` unless options_source names
  # one of OPTIONS_SOURCES, in which case the caller's list for that source is
  # used and an "unsure" choice is appended (see UNSURE_LABELS).
  #
  # `option_sources` is {source name => [{value,label}]}, passed in by the
  # caller rather than looked up here so this stays a pure read.
  #
  # yesno carries no stored options; its pair is implied.
  def options_for(option_sources: {})
    return YES_NO.map(&:dup) if question_type == "yesno"
    return options if options_source.blank?

    sourced = Array(option_sources[options_source])
    sourced + [ { "value" => "unsure", "label" => UNSURE_LABELS.fetch(options_source) } ]
  end

  private

  def options_are_well_formed
    unless options.is_a?(Array)
      errors.add(:options, "must be an array")
      return
    end

    options.each do |option|
      unless option.is_a?(Hash)
        errors.add(:options, "must be an array of objects")
        next
      end
      errors.add(:options, "needs a value on every option") if option["value"].to_s.strip.empty?
      errors.add(:options, "needs a label on every option") if option["label"].to_s.strip.empty?
    end

    values = options.filter_map { |o| o["value"] if o.is_a?(Hash) }
    errors.add(:options, "has duplicate values") if values.uniq.length != values.length
  end

  # A select or radio with nothing to pick from renders as a dead end. Skipped
  # when the choices come from elsewhere, since `options` is empty by design
  # then.
  def choice_questions_have_options
    return unless CHOICE_TYPES.include?(question_type)
    return if options_source.present?
    return if options.is_a?(Array) && options.any?

    errors.add(:options, "are required for a #{question_type} question")
  end

  # Answers are stored keyed by question_id, so renaming one on a live survey
  # silently detaches the responses already collected. New questions can still
  # be added to a published survey — that only means older responses have no
  # answer for them, which the tally queries already handle by skipping rows.
  def question_id_is_stable
    return unless persisted? && question_id_changed?
    return unless survey&.published?

    errors.add(:question_id,
      "cannot change once the survey is published — answers are stored under it")
  end
end
