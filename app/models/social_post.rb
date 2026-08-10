class SocialPost < ApplicationRecord
  include Feedable

  has_one_attached :image
  has_one_attached :avatar

  has_many :warehouse_social_media_posts,
    class_name: "Warehouse::SocialMediaPost",
    dependent: :nullify
  has_many :analytics_snapshots,
    through: :warehouse_social_media_posts,
    source: :metric_snapshots

  validates :external_id, presence: true, uniqueness: { scope: :type }
  validates :url, presence: true
  validates :account_handle, presence: true

  scope :by_account, ->(handle) { where(account_handle: handle) }

  def feed_published_at = posted_at

  # Store the STI subclass name (e.g. "SocialPost::X") in polymorphic type
  # instead of the base class "SocialPost"
  def self.polymorphic_name = name

  def self.feed_type_label
    raise NotImplementedError, "Subclasses must define feed_type_label"
  end
end
