class AddAccountToMetricsLinkedinAndSubstackStats < ActiveRecord::Migration[8.1]
  def change
    add_column :metrics_linkedin_stats, :account, :string, null: false, default: "build_canada"
    add_column :metrics_substack_stats, :account, :string, null: false, default: "build_canada"

    remove_index :metrics_linkedin_stats, :date
    remove_index :metrics_substack_stats, :date

    add_index :metrics_linkedin_stats, [ :account, :date ], unique: true
    add_index :metrics_substack_stats, [ :account, :date ], unique: true
  end
end
