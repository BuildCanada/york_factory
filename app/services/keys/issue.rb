module Keys
  # Creates a key (docs/public-interface-design.md §4.3, "Issuance"):
  #
  # 1. Validates the name, the scopes against the plan and the account's
  #    key limit.
  # 2. Asks the issuer (Bifrost in production) for a secret.
  # 3. Wraps it as bc_live_<secret>_<crc6>, stores only its digest, audits
  #    key.created and pushes the key to the edge.
  #
  # The raw key is returned once, in the result, and never stored or logged.
  # If the issuer is down, the savepoint rolls back and nothing is stored.
  class Issue
    Result = Data.define(:api_key, :raw_key) do
      def ok? = api_key.persisted? && raw_key.present?

      def inspect = "#<Keys::Issue::Result api_key=#{api_key&.id.inspect} ok=#{ok?}>"
      alias_method :to_s, :inspect
    end

    UNAVAILABLE_MESSAGE = "Key issuing is unavailable right now, so no key was created. Try again in a few minutes.".freeze

    def self.call(**) = new(**).call

    def initialize(account:, user:, name:, context:, scopes: ApiKey::DEFAULT_SCOPES, expires_in: ApiKey::EXPIRY_OPTIONS.fetch(ApiKey::DEFAULT_EXPIRY),
                   allowed_origins: [], allowed_ips: [], rotated_from: nil, issuer: KeyIssuers.default, enforce_limits: true)
      @account = account
      @user = user
      @name = name
      @context = context
      @scopes = scopes
      @expires_in = expires_in
      @allowed_origins = allowed_origins
      @allowed_ips = allowed_ips
      @rotated_from = rotated_from
      @issuer = issuer
      @enforce_limits = enforce_limits
    end

    def call
      api_key = build
      api_key.validate
      Keys::Policy.new(@account, @user).check_issue(api_key, enforce_limits: @enforce_limits && @rotated_from.nil?)
      return Result.new(api_key:, raw_key: nil) if api_key.errors.any?

      raw_key = nil
      issued = nil
      ApiKey.transaction(requires_new: true) do
        api_key.save!
        issued = @issuer.issue(api_key)
        raw_key = ApiKey::Token.wrap(issued.secret)
        api_key.update!(
          token_digest: ApiKey::Token.digest(raw_key),
          token_prefix: ApiKey::Token.display_prefix(raw_key),
          bifrost_vk_id: issued.bifrost_vk_id
        )
        AuditEvent.record!(@rotated_from ? "key.rotated_in" : "key.created",
          context: @context, account: @account, subject: api_key,
          metadata: { name: api_key.name, scopes: api_key.scopes, issuer: api_key.issuer, expires_at: api_key.expires_at&.iso8601,
                      rotated_from_id: @rotated_from&.id }.compact)
      end

      ActiveRecord.after_all_transactions_commit { after_commit(api_key) }
      Result.new(api_key:, raw_key:)
    rescue KeyIssuers::Unavailable, ApiKey::Token::InvalidSecret => error
      Rails.logger.error("[Keys::Issue] account #{@account.id}: #{error.class}: #{error.message}")
      api_key.errors.add(:base, UNAVAILABLE_MESSAGE)
      Result.new(api_key:, raw_key: nil)
    rescue ActiveRecord::ActiveRecordError
      # Bifrost issued a key but storing it failed: don't leave it active.
      deactivate_orphan(api_key, issued) if issued&.bifrost_vk_id
      raise
    end

    private

    def build
      @account.api_keys.new(
        user: @user,
        name: @name.to_s.strip,
        scopes: @scopes,
        issuer: @issuer.name,
        expires_at: @expires_in && Time.current + @expires_in,
        allowed_origins: @allowed_origins,
        allowed_ips: @allowed_ips,
        rotated_from: @rotated_from,
        # Placeholders until the issuer answers; replaced in the same savepoint.
        token_digest: "pending:#{SecureRandom.hex(16)}",
        token_prefix: "pending"
      )
    end

    def after_commit(api_key)
      Edge::Push.key(api_key)
      DevelopersMailer.with(api_key:, event: @rotated_from ? "rotated" : "created").key_changed.deliver_later unless @context.actor_kind == "system"
    end

    def deactivate_orphan(api_key, issued)
      orphan = api_key.dup.tap { |copy| copy.bifrost_vk_id = issued.bifrost_vk_id }
      @issuer.deactivate(orphan)
    rescue KeyIssuers::Unavailable
      nil # Keys::ReconcileBifrostJob deactivates orphans nightly.
    end
  end
end
