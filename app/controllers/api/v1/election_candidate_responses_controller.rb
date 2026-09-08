module Api
  module V1
    # Candidates' answers to an election questionnaire.
    #
    # Read-only, and deliberately the only public way to reach these: there is
    # no write path outside the CMS, because a candidate's answers are
    # attributed public statements about what they will do in office rather
    # than an anonymous submission.
    #
    # Gated twice, both on the same principle. The survey must be published —
    # a questionnaire is authored over days and must not leak while half
    # written — and each response must be published too, since staff transcribe
    # replies that arrive partial and unclear and a position goes out only
    # after review. preview_mode lets an admin see drafts, exactly as it does
    # for surveys and unpublished elections.
    class ElectionCandidateResponsesController < CmsBaseController
      before_action :set_election

      # Every published response for this election, newest question set first.
      # `ward` narrows to one council district, which is what a ward page wants.
      def index
        render json: { data: responses_scope.map { |response| serialize(response) } }
      end

      private

      def responses_scope
        scope = ::Warehouse::ElectionCandidateSurveyResponse
          .where(election_survey_id: surveys_scope.select(:id))
          .includes(:survey, candidate: :race)
        scope = scope.published unless preview_mode?
        filter_by_ward(scope).order(:election_candidate_id)
      end

      def surveys_scope
        scope = @election.surveys.where(audience: "candidate")
        scope = scope.published unless preview_mode?
        scope = scope.where(slug: params[:survey_slug]) if params[:survey_slug].present?
        scope
      end

      # District numbers are integers here and zero-padded ward keys ("04") on
      # the tracker, so the parameter is read as a number rather than matched
      # as a string.
      #
      # Base 10 explicitly: Integer() reads a leading zero as octal, so "08" and
      # "09" are not octal digits and come back nil — wards 8 and 9 would answer
      # empty rather than wrong, which is the kind of gap nobody reports.
      def filter_by_ward(scope)
        return scope if params[:ward].blank?

        ward = Integer(params[:ward], 10, exception: false)
        return scope.none if ward.nil?

        # Arel rather than a nested hash: the races table is schema-qualified
        # ("warehouse.election_races"), which a hash condition mis-parses.
        scope.joins(candidate: :race)
          .where(::Warehouse::ElectionRace.arel_table[:district_number].eq(ward))
      end

      # `entered_by` is deliberately not exposed: it names the staff member who
      # transcribed the reply, which is internal provenance rather than
      # anything a reader of the position needs.
      def serialize(response)
        candidate = response.candidate
        race = candidate&.race

        {
          candidate_name: display_name(candidate),
          full_name: candidate&.full_name,
          ward: race&.district_number,
          survey_slug: response.survey&.slug,
          survey_version: response.survey_version,
          answers: response.answers,
          explanations: response.explanations,
          source: response.source,
          published_at: response.published_at
        }
      end

      # "First Last", matching how the tracker renders a roster name — the two
      # are joined on it.
      def display_name(candidate)
        return nil if candidate.nil?

        parts = [ candidate.first_name, candidate.last_name ].compact_blank
        return parts.join(" ") if parts.any?

        last, first = candidate.full_name.to_s.split(",", 2).map(&:strip)
        first.present? ? "#{first} #{last}" : candidate.full_name
      end

      def set_election
        scope = preview_mode? ? ::Warehouse::Election.all : ::Warehouse::Election.published
        @election = scope.find_by!(slug: params[:election_slug])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end
    end
  end
end
