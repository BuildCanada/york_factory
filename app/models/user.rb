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
  validates :name, :postal_code, presence: true, if: :member?

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
end
