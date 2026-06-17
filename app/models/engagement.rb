class Engagement < ApplicationRecord
  include LinkedinVerified

  belongs_to :memo
  belongs_to :moderated_by, class_name: "User", optional: true

  enum :status, { pending: 0, approved: 1, rejected: 2 }, default: :pending

  scope :recent_first, -> { order(created_at: :desc) }

  private

  def revalidate_memo
    slug = Memo.where(id: memo_id).pick(:slug)
    RevalidateMemoJob.perform_later(slug) if slug
  end
end
