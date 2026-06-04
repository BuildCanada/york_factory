class CreateWarehouseOrganizationLineages < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.organization_lineages (
        id bigserial PRIMARY KEY,
        predecessor_id bigint NOT NULL REFERENCES warehouse.organizations(id),
        successor_id bigint NOT NULL REFERENCES warehouse.organizations(id),
        transition_year integer NOT NULL,
        transition_kind varchar NOT NULL,
        acknowledged_in_document_id bigint,
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT organization_lineages_distinct CHECK (predecessor_id <> successor_id),
        CONSTRAINT organization_lineages_kind_check
          CHECK (transition_kind IN ('rename','merge','split','absorb','spin_off','revived'))
      )
    SQL

    add_index "warehouse.organization_lineages",
              [ :predecessor_id, :successor_id, :transition_year, :transition_kind ],
              unique: true,
              name: "idx_organization_lineages_unique"
    add_index "warehouse.organization_lineages", :predecessor_id
    add_index "warehouse.organization_lineages", :successor_id
  end

  def down
    drop_table "warehouse.organization_lineages"
  end
end
