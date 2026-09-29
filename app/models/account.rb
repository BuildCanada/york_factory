# The unit that owns public data API keys and is billed and rate-limited
# (docs/public-interface-design.md §4.1). Each user gets a personal account;
# organization accounts share keys between members.
class Account < ApplicationRecord
  enum :kind, { personal: "personal", organization: "organization" }, validate: true

  belongs_to :personal_user, class_name: "User", optional: true
  has_many :memberships, class_name: "AccountMembership", dependent: :destroy
  has_many :users, through: :memberships
  has_many :api_keys, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 200 }
  validates :plan, inclusion: { in: Plan::NAMES }
  validates :plan_override, inclusion: { in: Plan::NAMES }, allow_nil: true
  validates :personal_user_id, presence: true, if: :personal?
  validates :personal_user_id, uniqueness: true, allow_nil: true

  scope :suspended, -> { where.not(suspended_at: nil) }

  # The user's personal account, created with an owner membership on first
  # use. Staff get the internal plan.
  def self.personal_for!(user)
    find_by(personal_user: user) || transaction(requires_new: true) do
      account = create!(
        personal_user: user,
        kind: "personal",
        name: user.name.presence || user.email,
        plan: user.admin? ? "internal" : "free"
      )
      account.memberships.create!(user:, role: "owner")
      account
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(personal_user: user)
  end

  def effective_plan_name
    if plan_override.present? && (plan_override_expires_at.nil? || plan_override_expires_at.future?)
      plan_override
    else
      plan
    end
  end

  def plan_definition = Plan.fetch(effective_plan_name)

  def suspended? = suspended_at.present?

  def terms_accepted? = terms_accepted_at.present?

  def membership_for(user) = memberships.find_by(user:)

  def manageable_by?(user) = membership_for(user)&.manages_keys? || false

  # Keys that count towards the plan's key limit: not revoked, not expired and
  # not being rotated out.
  def live_key_count = api_keys.live.count

  def audit_events = AuditEvent.where(account_id: id)
end
