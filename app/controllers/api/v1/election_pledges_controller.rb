module Api
  module V1
    # "I pledge to vote" submissions from the election tracker. Same
    # low-friction pattern as the newsletter signup: the pledge form submits
    # an email (+ optional name), which upserts a Subscriber and records one
    # pledge per subscriber per election — re-pledging updates the region and
    # timestamp. GET returns pledge counts by region (plus the total) for
    # displaying tallies.
    class ElectionPledgesController < CmsBaseController
      include SubscriberUpsertable

      before_action :set_election

      def index
        counts = @election.pledges_to_vote.group(:region).count
        render json: { data: { total: counts.values.sum, by_region: counts } }
      end

      # Lets the pledge form check a postal code before asking for an email, so
      # someone outside the region is told up front instead of after signing up.
      def eligibility
        result = @election.pledge_eligibility.check(params[:postal_code])

        render json: {
          eligible: result.eligible?,
          reason: result.reason,
          unverified_postal_code: result.indeterminate?,
          gated: @election.pledge_eligibility.gated?,
          region_name: @election.pledge_eligibility.region_name,
          postal_code: result.postal_code,
          city: result.city
        }
      end

      # Public lookup for a pledge's shareable page, by unguessable share
      # token. Exposes the pledger's display name but never their email.
      def show
        pledge = @election.pledges_to_vote.includes(:subscriber).find_by(share_token: params[:id])
        return render json: { error: "Not found" }, status: :not_found unless pledge

        render json: {
          name: display_name(pledge.subscriber),
          region: pledge.region,
          pledged_at: pledge.pledged_at
        }
      end

      def create
        # A pledge must carry everything the HubSpot member-join form requires
        # (first + last name, email, postal code), so the subscriber's form
        # submission can never be rejected for missing required fields.
        if (errors = missing_field_errors).any?
          return render json: { errors: errors }, status: :unprocessable_entity
        end

        # Only residents of the jurisdiction holding this election can pledge
        # in it, judged from the submitted postal code
        # (Election::PledgeEligibility). Checked before the subscriber saves:
        # an eligible pledger's stamp submits the HubSpot pledge form, so
        # their save must not also submit the subscriber form (see
        # Subscriber#pledging).
        eligibility = @election.pledge_eligibility.check(params[:postal_code])

        subscriber = find_or_build_subscriber(source: "pledge")
        subscriber.pledging = eligibility.eligible?
        unless subscriber.save
          return render json: { errors: subscriber.errors.full_messages }, status: :unprocessable_entity
        end

        # Someone outside the region can't pledge — we still keep the
        # subscriber (newsletter signup) but record no pledge, and signal the
        # client to redirect them to explore instead.
        unless eligibility.eligible?
          return render json: {
            outside_region: true,
            # Retained for the Toronto pledge form, which shipped against it.
            outside_toronto: @election.jurisdiction.slug == "toronto",
            region_name: @election.pledge_eligibility.region_name,
            reason: eligibility.reason,
            unverified_postal_code: eligibility.indeterminate?,
            subscribed: true,
            name: display_name(subscriber)
          }, status: :ok
        end

        pledge = @election.pledges_to_vote.find_or_initialize_by(subscriber: subscriber)
        newly_pledged = pledge.new_record?
        pledge.assign_attributes(region: params[:region], pledged_at: Time.current)

        if pledge.save
          render json: {
            region: pledge.region,
            pledged_at: pledge.pledged_at,
            share_token: pledge.share_token,
            name: display_name(subscriber),
            region_count: @election.pledges_to_vote.where(region: pledge.region).count
          }, status: newly_pledged ? :created : :ok
        else
          render json: { errors: pledge.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      # An unpublished election takes no pledges — it isn't public yet.
      def set_election
        scope = preview_mode? ? ::Warehouse::Election.all : ::Warehouse::Election.published
        @election = scope.find_by!(slug: params[:election_slug])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def missing_field_errors
        errors = []
        errors << "Email is required" if params[:email].blank?
        first, last = split_name(params[:name])
        errors << "Full name (first and last) is required" if first.blank? || last.blank?
        errors << "Postal code is required" if params[:postal_code].blank?
        errors
      end

      # find_or_build_subscriber, split_name and display_name live in
      # SubscriberUpsertable — the survey endpoint needs the same behaviour.
    end
  end
end
