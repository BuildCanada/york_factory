class Endorsement < ApplicationRecord
  include LinkedinVerified

  belongs_to :memo, counter_cache: :endorsements_count

  after_commit :revalidate_memo, on: [ :create, :destroy ]

  private

  def revalidate_memo
    slug = Memo.where(id: memo_id).pick(:slug)
    RevalidateMemoJob.perform_later(slug) if slug
  end
end
