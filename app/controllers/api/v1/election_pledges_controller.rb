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

        subscriber = find_or_build_subscriber
        unless subscriber.save
          return render json: { errors: subscriber.errors.full_messages }, status: :unprocessable_entity
        end

        # Only City of Toronto residents can pledge in this election. Every
        # Toronto postal code — and only Toronto's — falls in the "M" forward
        # sortation area, so the first letter is a reliable boundary check.
        # We still keep the subscriber (newsletter signup) but record no
        # pledge, and signal the client to redirect them to explore instead.
        unless toronto_postal_code?
          return render json: {
            outside_toronto: true,
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

      def set_election
        @election = ::Warehouse::Election.find_by!(slug: params[:election_slug])
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

      # Reuses an existing subscriber row for the email (case-insensitive)
      # or builds one. A name or postal code on the pledge form fills in
      # blank subscriber fields but never overwrites what a subscriber
      # already told us.
      def find_or_build_subscriber
        email = params[:email].to_s.strip
        subscriber = Subscriber.where("LOWER(email) = ?", email.downcase).first ||
          Subscriber.new(email: email)

        first, last = split_name(params[:name])
        subscriber.first_name = first if subscriber.first_name.blank? && first.present?
        subscriber.last_name = last if subscriber.last_name.blank? && last.present?

        postal_code = params[:postal_code].to_s.strip.upcase
        subscriber.postal_code = postal_code if subscriber.postal_code.blank? && postal_code.present?

        subscriber.source ||= "pledge"
        %i[placement page_uri page_name hubspot_utk ip_address].each do |attr|
          subscriber[attr] = params[attr] if subscriber[attr].blank? && params[attr].present?
        end
        subscriber
      end

      # True when the submitted postal code is inside the City of Toronto (an
      # "M" forward sortation area). A blank/absent postal code takes the
      # legacy path (e.g. ward-scoped pledges that never collected one) and is
      # allowed through — the public pledge form always supplies one.
      def toronto_postal_code?
        postal = params[:postal_code].to_s.strip
        return true if postal.blank?

        postal.upcase.start_with?("M")
      end

      def split_name(raw)
        parts = raw.to_s.strip.split(/\s+/)
        return [ nil, nil ] if parts.empty?

        [ parts[0..-2].presence&.join(" ") || parts.first, parts.length > 1 ? parts.last : nil ]
      end

      def display_name(subscriber)
        [ subscriber.first_name, subscriber.last_name ].compact_blank.join(" ").presence
      end
    end
  end
end
