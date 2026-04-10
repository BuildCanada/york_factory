class SubstackPost < ApplicationRecord
  include Feedable

  has_one_attached :image

  validates :external_url, presence: true, uniqueness: true
  validates :title, presence: true

  def feed_published_at = posted_at

  def self.feed_type_label = "substack"
end
