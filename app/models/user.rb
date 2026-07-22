class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :trackable, :omniauthable, :jwt_authenticatable,
         jwt_revocation_strategy: JwtDenylist,
         omniauth_providers: [ :google_oauth2, :linkedin ]

  has_many :identities, dependent: :destroy

  enum :role, {
    member: "member",
    trade_barriers_editor: "trade_barriers_editor",
    admin: "admin",
    superadmin: "superadmin"
  }

  def admin?
    role.in?(%w[admin superadmin])
  end

  def can_edit_trade_barriers?
    role.in?(%w[trade_barriers_editor admin superadmin])
  end

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true, if: :member?
  # postal_code is NOT required to create an account: members self-register via
  # OAuth (Google/LinkedIn), which can't supply a postal code. It is required to
  # endorse/critique a memo — enforced at that boundary (Api::V1 engagement
  # controllers return 422 :postal_code_required) and collected in the member
  # profile form. validate_engagement_ready! is the shared gate.
  POSTAL_CODE_REGEX = /\A[ABCEGHJKLMNPRSTVXY]\d[A-Z][ \-]?\d[A-Z]\d\z/i

  validates :postal_code,
    format: { with: POSTAL_CODE_REGEX, message: "must be a valid Canadian postal code" },
    allow_blank: true

  before_save :normalize_postal_code

  # Resolves (and links) the user behind an external OAuth identity. Supports
  # multiple linked providers per user via the identities table.
  #
  # Resolution order:
  #   1. Identity already exists for (provider, uid) — return its user.
  #   2. An existing account has the same email — link a new identity onto it,
  #      preserving password login and any other already-linked providers. Only
  #      merged when the provider reports the email verified, to avoid linking
  #      (and thereby taking over) an account via an unverified address.
  #   3. Brand-new user + its first identity.
  #
  # Returns the (possibly unpersisted) user; callers check #persisted?.
  def self.from_omniauth(provider:, uid:, email:, name: nil, avatar_url: nil, email_verified: true)
    if (identity = Identity.find_by(provider:, uid:))
      return identity.user
    end

    user = find_by(email:) if email.present? && email_verified != false

    unless user
      user = new do |u|
        u.email = email
        u.password = Devise.friendly_token[0, 20]
        u.name = name
        u.avatar_url = avatar_url
      end
      return user unless user.save # validation failed (e.g. blank/duplicate email) — caller handles
    end

    user.identities.create(provider:, uid:, email:, avatar_url:)
    user.update(name:) if user.name.blank? && name.present?
    user.update(avatar_url:) if user.avatar_url.blank? && avatar_url.present?
    user
  rescue ActiveRecord::RecordNotUnique
    Identity.find_by(provider:, uid:)&.user
  end

  # Google Sign-In (API JWT path). Receives a plain hash from the tokeninfo
  # verification in Api::V1::Auth::SessionsController.
  def self.from_google(auth)
    from_omniauth(
      provider: auth[:provider],
      uid: auth[:uid],
      email: auth[:email],
      name: auth[:name],
      avatar_url: auth[:avatar_url],
      email_verified: auth.fetch(:email_verified, true)
    )
  end

  # LinkedIn "Sign In with OpenID Connect" (browser OmniAuth path). The gem's
  # info hash omits a combined name, so read it from the raw userinfo and fall
  # back to first/last.
  def self.from_linkedin(auth)
    info = auth.info
    raw = auth.dig("extra", "raw_info").to_h
    full_name = raw["name"].presence ||
      [ info.first_name, info.last_name ].compact_blank.join(" ").presence

    from_omniauth(
      provider: "linkedin",
      uid: auth.uid,
      email: info.email,
      name: full_name,
      avatar_url: info.picture_url,
      email_verified: raw["email_verified"] != false
    )
  end

  # True once the user has the data required to publicly engage with a memo.
  def engagement_ready?
    postal_code.present?
  end

  private

  def normalize_postal_code
    return if postal_code.blank?

    cleaned = postal_code.upcase.gsub(/[\s\-]/, "")
    self.postal_code = "#{cleaned[0..2]} #{cleaned[3..5]}" if cleaned.length == 6
  end
end
