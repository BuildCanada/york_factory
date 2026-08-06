class SeedSpendingSources < ActiveRecord::Migration[8.1]
  def up
    load Rails.root.join("db/seeds/spending_sources.rb")
  end

  def down
    # Source records are operational data and may have been edited after seeding.
  end
end
