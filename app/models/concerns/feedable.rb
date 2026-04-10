module Feedable
  extend ActiveSupport::Concern

  included do
    has_one :feed_entry, as: :feedable, dependent: :destroy

    after_commit :sync_feed_entry, on: [ :create, :update ]
    after_commit :remove_feed_entry, on: :destroy
  end

  def feed_published_at
    respond_to?(:published_at) ? published_at : created_at
  end

  def feed_featured?
    respond_to?(:featured) ? featured : false
  end

  def self.feed_type_label
    name.demodulize.underscore
  end

  private

  def sync_feed_entry
    return unless should_appear_in_feed?

    if feed_entry
      feed_entry.update!(published_at: feed_published_at, featured: feed_featured?)
    else
      create_feed_entry!(published_at: feed_published_at, featured: feed_featured?)
    end
  end

  def remove_feed_entry
    feed_entry&.destroy
  end

  def should_appear_in_feed?
    return true unless respond_to?(:published?)

    published?
  end
end
