class TeamMember < ApplicationRecord
  include Translatable, Publishable

  extend Mobility
  translates :title, backend: :column

  extend FriendlyId
  friendly_id :name, use: :history

  has_one_attached :profile_photo
  has_many :authored_memos, class_name: "Memo", foreign_key: :author_id, dependent: :nullify
  has_many :co_authored_memos, class_name: "Memo", foreign_key: :co_author_id, dependent: :nullify

  validates :name, presence: true
  validates :role, inclusion: { in: %w[board advisor volunteer memo_author employee], allow_nil: true }

  scope :ordered, -> { order(:position) }
  scope :by_role, ->(role) { where(role: role) }

  # Memo authors should only appear when they have at least one memo associated.
  # Other roles are unaffected. memo_scope lets callers limit which memos count
  # (e.g. published-only on the public API).
  scope :with_associated_memos, ->(memo_scope = Memo.all) {
    base = memo_scope.unscope(:order, :select, :limit, :offset)
    authored_sql = base.where.not(author_id: nil).select(:author_id).to_sql
    co_authored_sql = base.where.not(co_author_id: nil).select(:co_author_id).to_sql
    where(
      "team_members.role IS DISTINCT FROM 'memo_author' " \
      "OR team_members.id IN (#{authored_sql}) " \
      "OR team_members.id IN (#{co_authored_sql})"
    )
  }

  translatable_fields :title
end
