class CreateTradeBarriers < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.jurisdictions (
        id bigserial PRIMARY KEY,
        name varchar NOT NULL,
        code varchar NOT NULL,
        level varchar NOT NULL,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL
    add_index "warehouse.jurisdictions", :code, unique: true

    create_table :trade_barriers_themes do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :trade_barriers_themes, :name, unique: true

    create_table :trade_barriers_agreements do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :summary
      t.text :description
      t.date :deadline
      t.date :launch_date
      t.string :source_url
      t.string :status, null: false, default: "awaiting_sponsorship"
      t.references :theme, null: false,
        foreign_key: { to_table: :trade_barriers_themes }
      t.timestamps
    end
    add_index :trade_barriers_agreements, :slug, unique: true
    add_index :trade_barriers_agreements, :status

    create_table :trade_barriers_agreement_jurisdictions do |t|
      t.references :agreement, null: false,
        foreign_key: { to_table: :trade_barriers_agreements }
      t.bigint :jurisdiction_id, null: false
      t.string :status, null: false, default: "unknown"
      t.text :notes
      t.timestamps
    end
    add_index :trade_barriers_agreement_jurisdictions, :jurisdiction_id
    add_index :trade_barriers_agreement_jurisdictions,
              [ :agreement_id, :jurisdiction_id ],
              unique: true,
              name: "idx_tb_agreement_jurisdictions_unique"
    execute <<~SQL
      ALTER TABLE trade_barriers_agreement_jurisdictions
      ADD CONSTRAINT fk_tb_aj_jurisdiction
      FOREIGN KEY (jurisdiction_id) REFERENCES warehouse.jurisdictions(id)
    SQL

    create_table :trade_barriers_agreement_histories do |t|
      t.references :agreement, null: false,
        foreign_key: { to_table: :trade_barriers_agreements }
      t.string :status, null: false
      t.date :date_entered, null: false
      t.timestamps
    end

    create_table :trade_barriers_jurisdiction_histories do |t|
      t.bigint :agreement_jurisdiction_id, null: false
      t.string :status, null: false
      t.date :date_entered, null: false
      t.timestamps
    end
    add_index :trade_barriers_jurisdiction_histories,
              :agreement_jurisdiction_id,
              name: "idx_tb_jurisdiction_histories_aj_id"
    execute <<~SQL
      ALTER TABLE trade_barriers_jurisdiction_histories
      ADD CONSTRAINT fk_tb_jh_aj
      FOREIGN KEY (agreement_jurisdiction_id)
      REFERENCES trade_barriers_agreement_jurisdictions(id)
      ON DELETE CASCADE
    SQL
  end

  def down
    drop_table :trade_barriers_jurisdiction_histories
    drop_table :trade_barriers_agreement_histories
    drop_table :trade_barriers_agreement_jurisdictions
    drop_table :trade_barriers_agreements
    drop_table :trade_barriers_themes
    execute "DROP TABLE IF EXISTS warehouse.jurisdictions"
  end
end
