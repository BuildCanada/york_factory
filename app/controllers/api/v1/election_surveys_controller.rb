module Api
  module V1
    # Survey definitions — the questions the tracker renders.
    #
    # These used to live in the tracker (surveyData.ts) and moved here when
    # candidates started answering surveys too, since an admin-entered candidate
    # questionnaire has to render the question set as a form in this app.
    #
    # Read-only. Resident answers are written through
    # ElectionSurveyResponsesController; candidate answers have no public write
    # path at all and are entered in the CMS.
    class ElectionSurveysController < CmsBaseController
      before_action :set_election

      # Every published survey for an election, without questions — enough to
      # know what exists and link to it.
      def index
        render json: { data: surveys_scope.map { |survey| summary(survey) } }
      end

      # One survey with its full question set, grouped into steps and ready to
      # render. Ward-sourced options are resolved here, so the choices track the
      # election's council races instead of a copy frozen at authoring time.
      def show
        survey = surveys_scope.find_by(slug: params[:slug])
        return render json: { error: "Not found" }, status: :not_found if survey.nil?

        render json: {
          data: summary(survey).merge(
            steps: survey.steps(ward_options: @election.ward_options)
          )
        }
      end

      private

      # An unpublished survey is not public — a candidate questionnaire is
      # authored over days in the CMS and must not appear on the site until it is
      # finished. preview_mode lets staff see drafts, matching how unpublished
      # elections are handled.
      def surveys_scope
        scope = @election.surveys
        scope = scope.published unless preview_mode?
        scope = scope.where(audience: params[:audience]) if params[:audience].present?
        scope.order(:audience, :slug)
      end

      def summary(survey)
        {
          slug: survey.slug,
          audience: survey.audience,
          version: survey.version,
          meta: survey.meta,
          question_count: survey.questions.size,
          published_at: survey.published_at
        }
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
