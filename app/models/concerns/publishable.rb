module Publishable
  extend ActiveSupport::Concern

  included do
    scope :published, -> { where.not(published_at: nil).where("published_at <= ?", Time.current) }
    scope :draft, -> { where(published_at: nil).or(where("published_at > ?", Time.current)) }
  end

  def published?
    published_at.present? && published_at <= Time.current
  end

  def scheduled?
    published_at.present? && published_at > Time.current
  end

  def draft?
    published_at.nil?
  end

  def publish_status
    if draft?
      "draft"
    elsif scheduled?
      "scheduled"
    else
      "published"
    end
  end
end
