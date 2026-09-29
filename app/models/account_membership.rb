class AccountMembership < ApplicationRecord
  belongs_to :account
  belongs_to :user

  enum :role, { owner: "owner", admin: "admin", member: "member" }, validate: true

  validates :user_id, uniqueness: { scope: :account_id }

  # Owners and admins manage keys; members can only see them.
  def manages_keys? = owner? || admin?
end
