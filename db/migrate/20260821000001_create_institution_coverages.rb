class CreateInstitutionCoverages < ActiveRecord::Migration[8.0]
  def change
    create_table "warehouse.institution_coverages" do |t|
      t.references :institution_release, null: false, foreign_key: { to_table: "warehouse.institution_releases" }
      t.references :institution_source, null: true, foreign_key: { to_table: "warehouse.institution_sources" }
      t.string :scope_id, null: false
      t.string :subject, null: false
      t.string :status, null: false
      t.text :notes, null: false
      t.string :source_url
      t.timestamps

      t.index [ :institution_release_id, :scope_id, :subject ],
        unique: true, name: "index_institution_coverages_scope_subject"
      t.check_constraint "subject IN ('institutions','websites','geographies','relationships','financial-statements','annual-reports','statement-of-financial-information','financial-data-return','document-assets')",
        name: "institution_coverages_subject"
      t.check_constraint "status IN ('complete','partial','not-searched','not-found','unavailable','failed')",
        name: "institution_coverages_status"
    end

    execute <<~SQL
      ALTER TABLE warehouse.institution_coverages
        ADD CONSTRAINT fk_institution_coverages_source_release
        FOREIGN KEY (institution_release_id, institution_source_id)
        REFERENCES warehouse.institution_sources (institution_release_id, id);
    SQL
  end
end
