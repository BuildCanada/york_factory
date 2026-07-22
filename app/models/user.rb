class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :trackable, :omniauthable, :jwt_authenticatable,
         jwt_revocation_strategy: JwtDenylist,
         omniauth_providers: [ :google_oauth2, :linkedin ]

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

  def self.from_google(auth)
    where(provider: auth[:provider], uid: auth[:uid]).first_or_create do |user|
      user.email = auth[:email]
      user.password = Devise.friendly_token[0, 20]
      user.name = auth[:name]
      user.avatar_url = auth[:avatar_url]
    end
  rescue ActiveRecord::RecordNotUnique
    where(provider: auth[:provider], uid: auth[:uid]).first!
  end

  # Resolves the user behind a LinkedIn OIDC identity from the OmniAuth auth hash
  # (omniauth-linkedin-openid). The gem's info hash omits a combined name, so we
  # read it from the raw userinfo response and fall back to first/last.
  #
  # Resolution order:
  #   1. Already linked — a user with this (provider, uid).
  #   2. Existing account with the same email — link LinkedIn onto it so a
  #      username/password user keeps their password login and gains LinkedIn.
  #      Only merged when LinkedIn reports the email as verified, to avoid
  #      linking (and thereby taking over) an account via an unverified email.
  #   3. Brand-new user.
  #
  # Note: the schema stores a single provider/uid per user, so linking replaces
  # any prior OAuth identity on the matched account (e.g. a pre-existing Google
  # link); password-based accounts (provider nil) link cleanly.
  def self.from_linkedin(auth)
    info = auth.info
    raw = auth.dig("extra", "raw_info").to_h
    full_name = raw["name"].presence ||
      [ info.first_name, info.last_name ].compact_blank.join(" ").presence

    linked = find_by(provider: "linkedin", uid: auth.uid)
    return linked if linked

    if info.email.present? && raw["email_verified"] != false &&
        (existing = find_by(email: info.email))
      existing.provider = "linkedin"
      existing.uid = auth.uid
      existing.name = full_name if existing.name.blank?
      existing.avatar_url = info.picture_url if existing.avatar_url.blank?
      existing.save
      return existing
    end

    create do |user|
      user.provider = "linkedin"
      user.uid = auth.uid
      user.email = info.email
      user.password = Devise.friendly_token[0, 20]
      user.name = full_name
      user.avatar_url = info.picture_url
    end
  rescue ActiveRecord::RecordNotUnique
    find_by(provider: "linkedin", uid: auth.uid) || find_by(email: info.email)
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
