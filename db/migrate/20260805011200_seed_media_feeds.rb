class SeedMediaFeeds < ActiveRecord::Migration[8.1]
  def up
    load Rails.root.join("db/seeds/media_feeds.rb")
  end

  def down
    # Feed records are operational data and may have been edited in admin.
  end
end
