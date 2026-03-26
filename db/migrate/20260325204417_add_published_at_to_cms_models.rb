class AddPublishedAtToCmsModels < ActiveRecord::Migration[8.1]
  def change
    add_column :builders, :published_at, :datetime
    add_column :team_members, :published_at, :datetime
    add_column :tools, :published_at, :datetime
    add_column :faqs, :published_at, :datetime
    add_column :feed_items, :published_at, :datetime
    add_column :testimonials, :published_at, :datetime

    reversible do |dir|
      dir.up do
        %w[builders team_members tools faqs feed_items testimonials].each do |table|
          execute "UPDATE #{table} SET published_at = NOW() WHERE published_at IS NULL"
        end
      end
    end
  end
end
