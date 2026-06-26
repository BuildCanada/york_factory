class Engagement < ApplicationRecord
  belongs_to :memo
  belongs_to :user
  belongs_to :moderated_by, class_name: "User", optional: true

  enum :status, { pending: 0, approved: 1, rejected: 2 }, default: :pending

  # One engagement of each type per user per memo (a user may both endorse and
  # critique the same memo, hence :type — the STI column — is part of the key).
  validates :user_id, uniqueness: { scope: [ :memo_id, :type ] }

  scope :recent_first, -> { order(created_at: :desc) }

  # Identity now lives on the User; expose it through the association so
  # serializers and views read engagement.author_name / .postal_code.
  delegate :name, :postal_code, to: :user, prefix: :author, allow_nil: true

  private

  def revalidate_memo
    slug = Memo.where(id: memo_id).pick(:slug)
    RevalidateMemoJob.perform_later(slug) if slug
  end
end
