module Api
  module V1
    # Resident-survey submissions from the election tracker. Same low-friction
    # pattern as the newsletter signup and the vote pledge: the form submits an
    # email plus a bag of answers, which upserts a Subscriber and records one
    # response per subscriber per survey per election — re-submitting replaces
    # the answers rather than adding a row, so tallies count people.
    #
    # Unlike pledges, residency is NOT gated. A pledge to vote in a city you
    # don't live in is meaningless, so Election::PledgeEligibility turns those
    # away; an opinion about the city isn't, and turning residents away over a
    # postal-code centroid that landed on the wrong side of a municipal line
    # would cost real responses. Out-of-city answers are stored and left for
    # analysis to filter.
    class ElectionSurveyResponsesController < CmsBaseController
      include SubscriberUpsertable

      before_action :set_election

      # Public unauthenticated write, so it gets a ceiling. Generous enough
      # that a household behind one NAT can all answer, low enough that a
      # script can't stuff the sample.
      rate_limit to: 20, within: 1.hour, only: :create

      # Each requested question costs one grouped count query, and the tally
      # endpoint is a public unauthenticated read, so the list is capped rather
      # than trusted: an arbitrarily long one would hold a connection across
      # arbitrarily many sequential queries. Well above any survey we'd
      # actually publish, so a real client never meets this.
      MAX_TALLY_QUESTIONS = 50

      # Answer tallies for publishing results: {question_id => {answer => count}}.
      # Optionally narrowed to one ward via ?region=ward-12, which reads the
      # respondent's own answer, not the derived column, since that is the one
      # always populated.
      def index
        scope = @election.survey_responses.where(survey_slug: survey_slug)
        scope = scope.where(region: params[:region]) if params[:region].present?

        question_ids = Array(params[:question_ids].presence&.split(","))
          .map(&:strip).compact_blank.uniq.take(MAX_TALLY_QUESTIONS)
        tallies = question_ids.index_with { |id| scope.tally_answers(id) }

        render json: { data: { total: scope.count, tallies: tallies } }
      end

      def create
        if (errors = missing_field_errors).any?
          return render json: { errors: errors }, status: :unprocessable_entity
        end

        subscriber = find_or_build_subscriber(source: "survey")
        unless subscriber.save
          return render json: { errors: subscriber.errors.full_messages }, status: :unprocessable_entity
        end

        response_record = @election.survey_responses
          .find_or_initialize_by(subscriber: subscriber, survey_slug: survey_slug)
        newly_answered = response_record.new_record?

        postal_code = normalized_postal_code
        response_record.assign_attributes(
          answers: answers_param,
          survey_version: params[:survey_version].presence,
          region: params[:region].presence,
          derived_region: derive_region(postal_code),
          postal_code: postal_code,
          submitted_at: Time.current
        )

        if response_record.save
          render json: {
            survey_slug: response_record.survey_slug,
            region: response_record.region,
            derived_region: response_record.derived_region,
            submitted_at: response_record.submitted_at,
            name: submitted_display_name
          }, status: newly_answered ? :created : :ok
        else
          render json: { errors: response_record.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      # An unpublished election takes no responses — it isn't public yet.
      def set_election
        scope = preview_mode? ? ::Warehouse::Election.all : ::Warehouse::Election.published
        @election = scope.find_by!(slug: params[:election_slug])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def survey_slug
        params[:survey_slug].to_s.strip.presence || "default"
      end

      # The name echoed back for the confirmation greeting is the one submitted
      # with *this* request, never SubscriberUpsertable#display_name.
      # find_or_build_subscriber deliberately keeps a subscriber's stored name
      # over a blank form field, so serializing the subscriber here would
      # answer "do you know this address, and under what name?" for anyone who
      # posts an email they don't own — and this form asks for nothing but an
      # email, which makes that a very cheap lookup. Nil when the form didn't
      # collect a name, which the tracker already handles.
      def submitted_display_name
        split_name(params[:name]).compact_blank.join(" ").presence
      end

      # Answers arrive as a free-form bag keyed by the question ids the tracker
      # defines. Permitting them wholesale is deliberate — enumerating the keys
      # here would mean a deploy every time a question is reworded, which is
      # exactly the coupling the jsonb column exists to avoid. The model
      # applies structural limits (count, key and value length, string values).
      def answers_param
        raw = params[:answers]
        return {} unless raw.respond_to?(:to_unsafe_h) || raw.is_a?(Hash)

        (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw).to_h
      end

      # "m5v2t6" / "M5V  2T6" → "M5V 2T6". Stored canonically because this
      # column is what a later ward backfill re-derives from, and
      # warehouse.postal_codes keys on the spaced form — an unspaced value
      # would silently fail to join.
      #
      # Anything that isn't a postal code is dropped rather than stored dirty
      # (matching normalizePostalCode on the tracker side). Dropping, not
      # rejecting: a junk postal code must not cost us an otherwise complete
      # set of answers, and it can't be stored anyway — the column is
      # varchar(7), so keeping it would turn a bad field into a 500.
      def normalized_postal_code
        raw = params[:postal_code].to_s.strip.upcase.delete(" ").presence
        return nil unless raw&.match?(/\A[A-Z]\d[A-Z]\d[A-Z]\d\z/)

        "#{raw[0, 3]} #{raw[3, 3]}"
      end

      # Best-guess ward from the postal code, stored alongside what the
      # respondent picked so the two can be compared.
      #
      # A miss is never fatal: no postal code, an unknown one, or no ward layer
      # loaded for the city all leave `derived_region` null and the response is
      # still recorded with the self-reported ward. Null rows stay backfillable
      # from `postal_code` once a city's wards land.
      def derive_region(postal_code)
        return nil if postal_code.blank?

        result = ::Warehouse::BoundaryLookup.new.check(postal_code)
        return nil unless result.found?

        ward_number = result.boundary&.ward_number
        ward_number.present? ? "ward-#{ward_number.to_i}" : nil
      end

      def missing_field_errors
        errors = []
        errors << "Email is required" if params[:email].blank?
        errors << "Answers are required" if answers_param.empty?
        errors
      end
    end
  end
end
