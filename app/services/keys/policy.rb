module Keys
  # Who may hold which key on an account. Adds errors to the key rather than
  # raising, so the console can show them on the form.
  class Policy
    def initialize(account, user)
      @account = account
      @user = user
    end

    def check_issue(api_key, enforce_limits: true)
      check_account(api_key)
      check_scopes(api_key)
      check_key_limit(api_key) if enforce_limits
    end

    def check_update(api_key)
      check_account(api_key)
      check_scopes(api_key)
    end

    # The scopes this account's keys may be given.
    def grantable_scopes
      ApiKey::SCOPES.keys.select { |scope| grantable?(scope) }
    end

    def grantable?(scope)
      case scope
      when "read:persons" then @account.terms_accepted? && @account.plan_definition.persons
      # cms:drafts acts as the key's user, so only a personal account's own user gets it.
      when "cms:drafts" then @account.personal? && @account.personal_user_id == @user&.id
      else ApiKey::SCOPES.key?(scope)
      end
    end

    private

    def check_account(api_key)
      api_key.errors.add(:base, "This account is suspended#{": #{@account.suspended_reason}" if @account.suspended_reason.present?}") if @account.suspended?
    end

    def check_scopes(api_key)
      api_key.scopes.each do |scope|
        next if !ApiKey::SCOPES.key?(scope) || grantable?(scope)

        reason = scope == "read:persons" ? "needs the data terms accepted on the developer overview" : "isn't available to this account"
        api_key.errors.add(:scopes, "#{scope} #{reason}")
      end
    end

    def check_key_limit(api_key)
      limit = @account.plan_definition.key_limit
      return if @account.live_key_count < limit

      api_key.errors.add(:base, "The #{@account.plan_definition.label} plan allows #{limit} active #{'key'.pluralize(limit)}. Revoke one first.")
    end
  end
end
