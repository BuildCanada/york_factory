module Oauth
  # The OAuth clients an account has authorized, for the developer console
  # (docs/public-interface-design.md §4.4, "authorized MCP clients with
  # revoke"). One entry per client and user who authorized it, built from
  # the tokens that are still usable.
  class AuthorizedApps
    Entry = Data.define(:application, :user, :scopes, :resources, :authorized_at, :last_refreshed_at) do
      def id = application.id
    end

    def initialize(account, now: Time.current)
      @account = account
      @now = now
    end

    def entries
      tokens = Doorkeeper::AccessToken.public_api.usable(@now).where(account_id: @account.id).includes(:application).to_a
      return [] if tokens.empty?

      users = User.where(id: tokens.map(&:resource_owner_id).uniq).index_by(&:id)
      first_grants = Doorkeeper::AccessGrant.where(account_id: @account.id, application_id: tokens.map(&:application_id).uniq)
        .group(:application_id, :resource_owner_id).minimum(:created_at)

      tokens.group_by { |token| [ token.application_id, token.resource_owner_id ] }.filter_map do |(application_id, user_id), group|
        next if group.first.application.nil?

        Entry.new(
          application: group.first.application,
          user: users[user_id],
          scopes: group.flat_map { |token| token.scopes.to_a }.uniq.sort,
          resources: group.map(&:resource).uniq.sort,
          authorized_at: first_grants[[ application_id, user_id ]] || group.map(&:created_at).min,
          last_refreshed_at: group.map(&:created_at).max
        )
      end.sort_by { |entry| -entry.last_refreshed_at.to_f }
    end
  end
end
