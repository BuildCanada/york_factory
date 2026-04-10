class FeedEntry < ApplicationRecord
  delegated_type :feedable, types: %w[
    Memo Post Builder SubstackPost
    SocialPost::X SocialPost::Instagram SocialPost::InstagramReel SocialPost::TikTok
  ]

  scope :published, -> { where("published_at <= ?", Time.current) }
  scope :featured, -> { where(featured: true) }
  scope :by_type, ->(type) { where(feedable_type: type) }
  scope :chronological, -> { order(published_at: :desc) }
end
