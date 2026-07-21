module Api
  module V1
    # "I pledge to vote" submissions from the election tracker. Same
    # low-friction pattern as the newsletter signup: the pledge form submits
    # an email (+ optional name), which upserts a Subscriber and records one
    # pledge per subscriber per election — re-pledging updates the region and
    # timestamp. GET returns pledge counts by region (plus the total) for
    # displaying tallies.
    class ElectionPledgesController < CmsBaseController
      before_action :set_election

      def index
        counts = @election.pledges_to_vote.group(:region).count
        render json: { data: { total: counts.values.sum, by_region: counts } }
      end

      def create
        subscriber = find_or_build_subscriber
        unless subscriber.save
          return render json: { errors: subscriber.errors.full_messages }, status: :unprocessable_entity
        end

        pledge = @election.pledges_to_vote.find_or_initialize_by(subscriber: subscriber)
        newly_pledged = pledge.new_record?
        pledge.assign_attributes(region: params[:region], pledged_at: Time.current)

        if pledge.save
          render json: {
            region: pledge.region,
            pledged_at: pledge.pledged_at,
            region_count: @election.pledges_to_vote.where(region: pledge.region).count
          }, status: newly_pledged ? :created : :ok
        else
          render json: { errors: pledge.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_election
        @election = ::Warehouse::Election.find_by!(slug: params[:election_slug])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      # Reuses an existing subscriber row for the email (case-insensitive)
      # or builds one. A name on the pledge form fills in blank subscriber
      # names but never overwrites what a subscriber already told us.
      def find_or_build_subscriber
        email = params[:email].to_s.strip
        subscriber = Subscriber.where("LOWER(email) = ?", email.downcase).first ||
          Subscriber.new(email: email)

        first, last = split_name(params[:name])
        subscriber.first_name = first if subscriber.first_name.blank? && first.present?
        subscriber.last_name = last if subscriber.last_name.blank? && last.present?
        subscriber
      end

      def split_name(raw)
        parts = raw.to_s.strip.split(/\s+/)
        return [ nil, nil ] if parts.empty?

        [ parts[0..-2].presence&.join(" ") || parts.first, parts.length > 1 ? parts.last : nil ]
      end
    end
  end
end
