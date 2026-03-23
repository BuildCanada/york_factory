class AddScrapingProgressToRawIngestions < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_ingestions, :scraping_progress, :jsonb, default: {}
  end
end
