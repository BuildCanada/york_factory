class AddCsdAuthorityMapping < ActiveRecord::Migration[8.1]
  def up
    add_column "warehouse.institution_geography_snapshots", :classification_type, :string
    add_column "warehouse.institution_geography_snapshots", :authority_status, :string,
      null: false, default: "legacy"
    add_check_constraint "warehouse.institution_geography_snapshots",
      "authority_status IN ('legacy','not_applicable','verified','provisional','unresolved')",
      name: "institution_geo_snapshots_authority_status"

    add_column "warehouse.institution_geographies", :match_method, :string,
      null: false, default: "legacy"
    add_column "warehouse.institution_geographies", :confidence, :decimal, precision: 5, scale: 4
    add_column "warehouse.institution_geographies", :valid_from, :date
    add_column "warehouse.institution_geographies", :valid_to, :date
    add_column "warehouse.institution_geographies", :notes, :text
    add_check_constraint "warehouse.institution_geographies",
      "role IN ('governs','administers','serves','headquartered_in')",
      name: "institution_geographies_role_v2"
    remove_check_constraint "warehouse.institution_geographies", name: "institution_geographies_role"
    add_check_constraint "warehouse.institution_geographies",
      "match_method IN ('legacy','authoritative_crosswalk','source_assertion','exact_identifier','exact_name','jurisdictional_fallback')",
      name: "institution_geographies_match_method"
    add_check_constraint "warehouse.institution_geographies",
      "confidence IS NULL OR confidence BETWEEN 0 AND 1",
      name: "institution_geographies_confidence"
    add_check_constraint "warehouse.institution_geographies",
      "valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from",
      name: "institution_geographies_valid_range"

    remove_check_constraint "warehouse.institution_coverages", name: "institution_coverages_subject"
    add_check_constraint "warehouse.institution_coverages",
      "subject IN ('institutions','websites','geographies','relationships','financial-statements','annual-reports','statement-of-financial-information','financial-data-return','document-assets','csd-inventory','csd-authority-mapping')",
      name: "institution_coverages_subject"
  end

  def down
    remove_check_constraint "warehouse.institution_coverages", name: "institution_coverages_subject"
    add_check_constraint "warehouse.institution_coverages",
      "subject IN ('institutions','websites','geographies','relationships','financial-statements','annual-reports','statement-of-financial-information','financial-data-return','document-assets')",
      name: "institution_coverages_subject"

    remove_check_constraint "warehouse.institution_geographies", name: "institution_geographies_valid_range"
    remove_check_constraint "warehouse.institution_geographies", name: "institution_geographies_confidence"
    remove_check_constraint "warehouse.institution_geographies", name: "institution_geographies_match_method"
    remove_check_constraint "warehouse.institution_geographies", name: "institution_geographies_role_v2"
    add_check_constraint "warehouse.institution_geographies",
      "role IN ('governs','serves','headquartered_in')", name: "institution_geographies_role"
    remove_columns "warehouse.institution_geographies", :match_method, :confidence, :valid_from, :valid_to, :notes

    remove_check_constraint "warehouse.institution_geography_snapshots",
      name: "institution_geo_snapshots_authority_status"
    remove_columns "warehouse.institution_geography_snapshots", :classification_type, :authority_status
  end
end
