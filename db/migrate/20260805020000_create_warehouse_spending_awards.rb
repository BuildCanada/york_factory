class CreateWarehouseSpendingAwards < ActiveRecord::Migration[8.1]
  def change
    create_table "warehouse.spending_awards" do |t|
      t.references :source, null: false, foreign_key: { to_table: "warehouse.sources" }
      t.references :raw_ingestion, foreign_key: { to_table: "warehouse.raw_ingestions" }
      t.references :payer_organization, foreign_key: { to_table: "warehouse.organizations" }

      t.string :external_key, null: false
      t.string :award_type, null: false
      t.string :state, null: false, default: "published"
      t.string :language, null: false, default: "en"
      t.text :title, null: false
      t.text :description
      t.string :payer_name
      t.string :recipient_name
      t.string :recipient_type
      t.string :program_name
      t.string :program_key
      t.integer :fiscal_year
      t.timestamptz :occurred_at
      t.decimal :amount, precision: 20, scale: 2
      t.string :currency, null: false, default: "CAD"
      t.boolean :is_aggregated, null: false, default: false
      t.string :source_url
      t.string :province_code
      t.string :country_code
      t.jsonb :metadata, null: false, default: {}
      t.timestamptz :first_seen_at, null: false
      t.timestamptz :last_seen_at, null: false

      t.integer :search_revision, null: false, default: 0
      t.bigint :search_index_sequence
      t.timestamptz :search_synced_at
      t.string :search_content_hash
      t.string :search_embedding_model
      t.string :search_embedding_input_hash
      t.string :search_embedding_scope
      t.integer :search_embedding_input_tokens

      t.timestamps
    end

    add_index "warehouse.spending_awards", [ :source_id, :external_key ],
      unique: true, name: "idx_spending_awards_source_key"
    add_index "warehouse.spending_awards", [ :search_synced_at, :search_index_sequence ],
      name: "idx_spending_awards_search_sync"
    add_index "warehouse.spending_awards", :award_type
    add_index "warehouse.spending_awards", :fiscal_year
    add_index "warehouse.spending_awards", :recipient_name
    add_check_constraint "warehouse.spending_awards",
      "award_type IN ('contract', 'grant', 'contribution', 'transfer_payment')",
      name: "spending_awards_award_type"
    add_check_constraint "warehouse.spending_awards",
      "state IN ('published', 'withdrawn')",
      name: "spending_awards_state"
    add_check_constraint "warehouse.spending_awards",
      "search_revision >= 0",
      name: "spending_awards_revision_nonnegative"
  end
end
