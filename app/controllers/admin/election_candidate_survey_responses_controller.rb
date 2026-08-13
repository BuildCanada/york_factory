module Admin
  # Staff entry of a candidate's questionnaire answers.
  #
  # This is the ONLY write path for candidate responses, by design. A candidate's
  # answers are attributed public statements, and warehouse.election_candidates
  # carries an `email`, so a public endpoint keyed on candidate email would let
  # anyone publish positions in a candidate's name. Answers arrive by email, a
  # form, or phone, and staff transcribe them here — `source` and `entered_by`
  # record which, so a published position is always traceable.
  class ElectionCandidateSurveyResponsesController < BaseController
    before_action :set_candidate
    before_action :set_survey
    before_action :set_response

    def edit; end

    def update
      @response.assign_attributes(response_params)
      @response.answers = submitted_answers
      @response.explanations = submitted_explanations
      @response.entered_by = current_user.email
      @response.submitted_at ||= Time.current
      @response.survey_version = @survey.version if @response.survey_version.blank?

      if @response.save
        redirect_to admin_election_path(@election, anchor: "candidate-#{@candidate.id}"),
          notice: "Questionnaire saved for #{@candidate.display_name}."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @response.destroy!
      redirect_to admin_election_path(@election, anchor: "candidate-#{@candidate.id}"),
        notice: "Questionnaire cleared for #{@candidate.display_name}."
    end

    private

    def set_candidate
      @candidate = Warehouse::ElectionCandidate.find(params[:election_candidate_id])
      @election = @candidate.race.election
    end

    # Defaults to the election's candidate questionnaire, since there is
    # normally one. An explicit ?survey_slug= picks another.
    def set_survey
      scope = @election.surveys.where(audience: "candidate")
      @survey = if params[:survey_slug].present?
        scope.find_by!(slug: params[:survey_slug])
      else
        scope.order(:slug).first
      end

      return if @survey

      redirect_to admin_election_path(@election),
        alert: "This election has no candidate questionnaire yet. Add one before entering answers."
    end

    def set_response
      return if @survey.nil?

      @response = @survey.candidate_responses
        .find_or_initialize_by(candidate: @candidate)
      @response.source ||= "email"
    end

    def response_params
      params.require(:warehouse_election_candidate_survey_response)
        .permit(:status, :source, :notes, :survey_version)
    end

    # Answers come in as answers[question_id]. Blanks are dropped rather than
    # stored as "": a question a candidate didn't answer must read as unanswered,
    # which is what #unanswered_question_ids reports on and what the public site
    # renders as "no response".
    def submitted_answers
      permitted_hash(:answers)
    end

    def submitted_explanations
      permitted_hash(:explanations)
    end

    def permitted_hash(key)
      raw = params[key]
      return {} if raw.blank?

      hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      # Only keys this survey actually defines are kept, so a stale form posted
      # after a question was removed can't reintroduce it. The model validates
      # this too; filtering here means the staff member gets their edit saved
      # rather than a validation error about a field they never touched.
      known = @survey.questions.map(&:question_id).to_set
      hash.to_h.filter_map do |question_id, value|
        next unless known.include?(question_id.to_s)
        next if value.to_s.strip.empty?

        [ question_id.to_s, value.to_s.strip ]
      end.to_h
    end
  end
end
