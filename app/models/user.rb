class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :trackable, :omniauthable, :jwt_authenticatable,
         jwt_revocation_strategy: JwtDenylist,
         omniauth_providers: [ :google_oauth2 ]

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

  # Upserts the user behind a verified LinkedIn OIDC identity (the decoded
  # id_token claims: sub/name/email/picture). Mirrors from_google.
  def self.from_linkedin(identity)
    where(provider: "linkedin", uid: identity["sub"]).first_or_create do |user|
      user.email = identity["email"]
      user.password = Devise.friendly_token[0, 20]
      user.name = identity["name"]
      user.avatar_url = identity["picture"]
    end
  rescue ActiveRecord::RecordNotUnique
    where(provider: "linkedin", uid: identity["sub"]).first!
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
