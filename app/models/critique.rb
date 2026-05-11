class Critique < ApplicationRecord
  include LinkedinVerified

  belongs_to :memo
  belongs_to :moderated_by, class_name: "User", optional: true

  enum :status, { pending: 0, approved: 1, rejected: 2 }

  validates :body, presence: true, length: { maximum: 10_000 }

  scope :recent_first, -> { order(created_at: :desc) }

  after_save :sync_approved_counter, if: :saved_change_to_status?
  after_destroy :decrement_counter_if_approved
  after_commit :maybe_revalidate_memo

  def approve!(user)
    update!(status: :approved, moderated_by: user, moderated_at: Time.current, published_at: published_at || Time.current)
  end

  def reject!(user)
    update!(status: :rejected, moderated_by: user, moderated_at: Time.current)
  end

  private

  def sync_approved_counter
    before, after = saved_change_to_status
    # Rails enum: with the integer column, before/after are integers on create
    # and strings on update. Normalize to strings.
    before = Critique.statuses.key(before) if before.is_a?(Integer)
    after  = Critique.statuses.key(after)  if after.is_a?(Integer)
    became_approved = (after == "approved" && before != "approved")
    left_approved   = (before == "approved" && after != "approved")
    if became_approved
      Memo.increment_counter(:approved_critiques_count, memo_id)
    elsif left_approved
      Memo.decrement_counter(:approved_critiques_count, memo_id)
    end
  end

  def decrement_counter_if_approved
    Memo.decrement_counter(:approved_critiques_count, memo_id) if approved?
  end

  def maybe_revalidate_memo
    # Revalidate when the memo's public view changes:
    #   - a critique is approved or unapproved (status crossed the approved boundary)
    #   - an approved critique is destroyed
    return unless previous_changes.key?("status") || destroyed?

    affects_public_view = if destroyed?
      approved?
    else
      before, after = previous_changes["status"]
      before = Critique.statuses.key(before) if before.is_a?(Integer)
      after  = Critique.statuses.key(after)  if after.is_a?(Integer)
      before == "approved" || after == "approved"
    end
    return unless affects_public_view

    slug = Memo.where(id: memo_id).pick(:slug)
    RevalidateMemoJob.perform_later(slug) if slug
  end
end
