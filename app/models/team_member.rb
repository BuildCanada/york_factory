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
  validates :role, inclusion: { in: %w[board team volunteer advisor], allow_nil: true }

  scope :ordered, -> { order(:position) }
  scope :by_role, ->(role) { where(role: role) }

  translatable_fields :title
end
