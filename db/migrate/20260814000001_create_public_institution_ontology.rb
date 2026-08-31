class CreatePublicInstitutionOntology < ActiveRecord::Migration[8.1]
  def up
    create_releases
    create_sources
    create_institutions
    create_identifiers
    create_relationships
    create_geography_snapshots
    create_institution_geographies
    create_documents
    create_document_assets
    add_release_consistency_foreign_keys
  end

  def down
    drop_table "warehouse.institution_document_assets"
    drop_table "warehouse.institution_documents"
    drop_table "warehouse.institution_geographies"
    drop_table "warehouse.institution_geography_snapshots"
    drop_table "warehouse.institution_relationships"
    drop_table "warehouse.institution_identifiers"
    drop_table "warehouse.institutions"
    drop_table "warehouse.institution_sources"
    drop_table "warehouse.institution_releases"
  end

  private

  def create_releases
    create_table "warehouse.institution_releases" do |t|
      t.string :version, null: false
      t.date :effective_on, null: false
      t.string :schema_version, null: false, default: "1.0"
      t.datetime :published_at, null: false
      t.integer :geography_vintage, null: false, default: 2021
      t.text :attribution, null: false
      t.timestamps
    end
    add_index "warehouse.institution_releases", :version, unique: true
    add_check_constraint "warehouse.institution_releases",
      "version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'",
      name: "institution_releases_version_format"
    add_check_constraint "warehouse.institution_releases",
      "effective_on = version::date",
      name: "institution_releases_version_matches_effective_on"
  end

  def create_sources
    create_table "warehouse.institution_sources" do |t|
      t.bigint :institution_release_id, null: false
      t.string :canonical_id, null: false
      t.string :publisher_name, null: false
      t.string :title_en
      t.string :title_fr
      t.text :url, null: false
      t.datetime :retrieved_at, null: false
      t.string :license
      t.text :attribution
      t.string :languages, array: true, null: false, default: []
      t.timestamps
    end
    add_foreign_key "warehouse.institution_sources", "warehouse.institution_releases"
    add_index "warehouse.institution_sources", [ :institution_release_id, :id ], unique: true,
      name: "idx_institution_sources_release_id"
    add_index "warehouse.institution_sources", [ :institution_release_id, :canonical_id ], unique: true,
      name: "idx_institution_sources_release_canonical"
    add_index "warehouse.institution_sources", [ :institution_release_id, :url ]
    add_check_constraint "warehouse.institution_sources",
      "canonical_id = lower(canonical_id) AND canonical_id ~ '^ca/sources/[a-z0-9]+(-[a-z0-9]+)*(/[a-z0-9]+(-[a-z0-9]+)*)*$'",
      name: "institution_sources_canonical_id_format"
    add_check_constraint "warehouse.institution_sources", "url ~ '^https?://'",
      name: "institution_sources_url"
  end

  def create_institutions
    create_table "warehouse.institutions" do |t|
      t.bigint :institution_release_id, null: false
      t.bigint :institution_source_id
      t.string :canonical_id, null: false
      t.string :name_en
      t.string :name_fr
      t.text :website_url
      t.string :institution_type, null: false
      t.string :legal_form
      t.string :government_level, null: false
      t.string :status, null: false, default: "unknown"
      t.text :contact_email
      t.text :contact_phone
      t.text :civic_address
      t.text :mailing_address
      t.date :active_from
      t.date :active_to
      t.text :description_en
      t.text :description_fr
      t.integer :fiscal_year_start_month
      t.string :default_currency, limit: 3, default: "CAD"
      t.timestamps
    end
    add_foreign_key "warehouse.institutions", "warehouse.institution_releases"
    add_index "warehouse.institutions", [ :institution_release_id, :id ], unique: true,
      name: "idx_institutions_release_id"
    add_index "warehouse.institutions", [ :institution_release_id, :canonical_id ], unique: true,
      name: "idx_institutions_release_canonical"
    add_check_constraint "warehouse.institutions",
      "canonical_id = lower(canonical_id) AND canonical_id ~ '^ca/[a-z0-9]+(-[a-z0-9]+)*(/[a-z0-9]+(-[a-z0-9]+)*)*$'",
      name: "institutions_canonical_id_format"
    add_check_constraint "warehouse.institutions",
      "canonical_id !~ '^ca/(sources|geography)/' AND canonical_id !~ '/documents/'",
      name: "institutions_reserved_namespaces"
    add_check_constraint "warehouse.institutions", "name_en IS NOT NULL OR name_fr IS NOT NULL",
      name: "institutions_has_name"
    add_check_constraint "warehouse.institutions", "website_url IS NULL OR website_url ~ '^https?://'",
      name: "institutions_website_url"
    add_check_constraint "warehouse.institutions",
      "institution_type IN ('government','department','ministry','agency','authority','board','commission','crown_corporation','government_business_enterprise','police_service','fire_service','public_library','health_authority','education_authority','corporation','other')",
      name: "institutions_type"
    add_check_constraint "warehouse.institutions",
      "government_level IN ('federal','provincial','territorial','regional','municipal','first_nation','inuit','metis','joint','other')",
      name: "institutions_government_level"
    add_check_constraint "warehouse.institutions",
      "status IN ('active','inactive','dissolved','proposed','unknown')",
      name: "institutions_status"
    add_check_constraint "warehouse.institutions",
      "active_to IS NULL OR active_from IS NULL OR active_to >= active_from",
      name: "institutions_active_range"
    add_check_constraint "warehouse.institutions",
      "fiscal_year_start_month IS NULL OR fiscal_year_start_month BETWEEN 1 AND 12",
      name: "institutions_fiscal_month"
  end

  def create_identifiers
    create_table "warehouse.institution_identifiers" do |t|
      t.bigint :institution_release_id, null: false
      t.bigint :institution_id, null: false
      t.bigint :institution_source_id
      t.string :scheme, null: false
      t.string :value, null: false
      t.boolean :preferred, null: false, default: false
      t.timestamps
    end
    add_foreign_key "warehouse.institution_identifiers", "warehouse.institution_releases"
    add_index "warehouse.institution_identifiers", [ :institution_id, :scheme ],
      name: "idx_institution_identifiers_institution_scheme"
    add_index "warehouse.institution_identifiers", [ :institution_release_id, :scheme, :value ], unique: true,
      name: "idx_institution_identifiers_release_value"
    add_index "warehouse.institution_identifiers", [ :institution_release_id, :institution_id, :scheme ],
      unique: true, where: "preferred", name: "idx_institution_identifiers_preferred"
    add_check_constraint "warehouse.institution_identifiers",
      "scheme ~ '^[a-z0-9]+([._-][a-z0-9]+)*$'",
      name: "institution_identifiers_scheme_format"
  end

  def create_relationships
    create_table "warehouse.institution_relationships" do |t|
      t.bigint :institution_release_id, null: false
      t.bigint :source_institution_id, null: false
      t.bigint :target_institution_id, null: false
      t.bigint :institution_source_id
      t.string :relationship_type, null: false
      t.boolean :primary, null: false, default: false
      t.decimal :ownership_percentage, precision: 7, scale: 4
      t.string :ownership_basis
      t.date :valid_from
      t.date :valid_to
      t.text :notes
      t.timestamps
    end
    add_foreign_key "warehouse.institution_relationships", "warehouse.institution_releases"
    add_index "warehouse.institution_relationships", [ :institution_release_id, :relationship_type ],
      name: "idx_institution_relationships_release_type"
    add_index "warehouse.institution_relationships", [ :institution_release_id, :source_institution_id ],
      unique: true, where: '"primary"', name: "idx_institution_relationships_primary_parent"
    execute <<~SQL
      CREATE UNIQUE INDEX idx_institution_relationships_unique
        ON warehouse.institution_relationships
          (institution_release_id, source_institution_id, target_institution_id,
           relationship_type, valid_from)
        NULLS NOT DISTINCT
    SQL
    add_check_constraint "warehouse.institution_relationships",
      "source_institution_id <> target_institution_id", name: "institution_relationships_distinct"
    add_check_constraint "warehouse.institution_relationships",
      "relationship_type IN ('administrative_parent','reports_to','owned_by','controlled_by','consolidated_into','governed_by','operated_by','member_of','succeeds')",
      name: "institution_relationships_type"
    add_check_constraint "warehouse.institution_relationships",
      "ownership_percentage IS NULL OR ownership_percentage BETWEEN 0 AND 100",
      name: "institution_relationships_ownership_percentage"
    add_check_constraint "warehouse.institution_relationships",
      "ownership_basis IS NULL OR ownership_basis IN ('equity','voting','statutory','board_appointment','accounting_control','other')",
      name: "institution_relationships_ownership_basis"
    add_check_constraint "warehouse.institution_relationships",
      "valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from",
      name: "institution_relationships_valid_range"
    add_check_constraint "warehouse.institution_relationships",
      "NOT \"primary\" OR relationship_type = 'administrative_parent'",
      name: "institution_relationships_primary_type"
  end

  def create_geography_snapshots
    execute <<~SQL
      CREATE TABLE warehouse.institution_geography_snapshots (
        id bigserial PRIMARY KEY,
        institution_release_id bigint NOT NULL REFERENCES warehouse.institution_releases(id),
        canonical_id varchar NOT NULL,
        code_system varchar NOT NULL,
        geo_uid varchar NOT NULL,
        boundary_type varchar NOT NULL,
        name_en varchar,
        name_fr varchar,
        province_code varchar(2),
        census_year integer NOT NULL,
        geometry geography(MultiPolygon, 4326),
        population integer,
        area_sq_km decimal,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL
    add_index "warehouse.institution_geography_snapshots", [ :institution_release_id, :id ], unique: true,
      name: "idx_institution_geo_snapshots_release_id"
    add_index "warehouse.institution_geography_snapshots", [ :institution_release_id, :canonical_id ], unique: true,
      name: "idx_institution_geo_snapshots_release_canonical"
    add_index "warehouse.institution_geography_snapshots",
      [ :institution_release_id, :boundary_type, :geo_uid, :census_year ], unique: true,
      name: "idx_institution_geo_snapshots_release_uid"
    execute "CREATE INDEX idx_institution_geo_snapshots_geometry ON warehouse.institution_geography_snapshots USING gist (geometry)"
    add_check_constraint "warehouse.institution_geography_snapshots",
      "canonical_id = lower(canonical_id) AND canonical_id ~ '^ca/geography/[a-z0-9]+(-[a-z0-9]+)*/[a-z0-9]+(-[a-z0-9]+)*$'",
      name: "institution_geo_snapshots_canonical_id_format"
  end

  def create_institution_geographies
    create_table "warehouse.institution_geographies" do |t|
      t.bigint :institution_release_id, null: false
      t.bigint :institution_id, null: false
      t.bigint :institution_geography_snapshot_id, null: false
      t.bigint :institution_source_id
      t.string :role, null: false
      t.timestamps
    end
    add_foreign_key "warehouse.institution_geographies", "warehouse.institution_releases"
    add_index "warehouse.institution_geographies",
      [ :institution_release_id, :institution_id, :institution_geography_snapshot_id, :role ],
      unique: true, name: "idx_institution_geographies_unique"
    add_check_constraint "warehouse.institution_geographies",
      "role IN ('governs','serves','headquartered_in')", name: "institution_geographies_role"
  end

  def create_documents
    create_table "warehouse.institution_documents" do |t|
      t.bigint :institution_release_id, null: false
      t.bigint :institution_id, null: false
      t.bigint :institution_source_id, null: false
      t.string :canonical_id, null: false
      t.string :document_type, null: false
      t.string :document_variant, null: false, default: "general"
      t.string :title_en
      t.string :title_fr
      t.date :fiscal_period_start
      t.date :fiscal_period_end
      t.date :published_on
      t.text :source_page_url
      t.text :download_url
      t.text :notes
      t.timestamps
    end
    add_foreign_key "warehouse.institution_documents", "warehouse.institution_releases"
    add_index "warehouse.institution_documents", [ :institution_release_id, :id ], unique: true,
      name: "idx_institution_documents_release_id"
    add_index "warehouse.institution_documents", [ :institution_release_id, :canonical_id ], unique: true,
      name: "idx_institution_documents_release_canonical"
    add_check_constraint "warehouse.institution_documents",
      "canonical_id = lower(canonical_id) AND canonical_id ~ '^ca/[a-z0-9]+(-[a-z0-9]+)*(/[a-z0-9]+(-[a-z0-9]+)*)*$'",
      name: "institution_documents_canonical_id_format"
    add_check_constraint "warehouse.institution_documents",
      "canonical_id LIKE 'ca/%/documents/%' AND canonical_id NOT LIKE 'ca/sources/%'",
      name: "institution_documents_canonical_id_namespace"
    add_check_constraint "warehouse.institution_documents",
      "document_type IN ('annual-report','financial-statements','statement-of-financial-information','financial-data-return','auditor-report','remuneration-report','other')",
      name: "institution_documents_type"
    add_check_constraint "warehouse.institution_documents",
      "document_variant ~ '^[a-z0-9]+(-[a-z0-9]+)*$'", name: "institution_documents_variant"
    add_check_constraint "warehouse.institution_documents",
      "fiscal_period_end IS NULL OR fiscal_period_start IS NULL OR fiscal_period_end >= fiscal_period_start",
      name: "institution_documents_fiscal_range"
  end

  def create_document_assets
    create_table "warehouse.institution_document_assets" do |t|
      t.bigint :institution_release_id, null: false
      t.bigint :institution_document_id, null: false
      t.string :content_sha256, null: false
      t.string :asset_role, null: false, default: "unknown"
      t.integer :part_index
      t.integer :part_count
      t.boolean :preferred, null: false, default: false
      t.text :download_url, null: false
      t.datetime :retrieved_at, null: false
      t.string :archive_path, null: false
      t.string :mime_type, null: false
      t.bigint :byte_size, null: false
      t.string :rights_status, null: false, default: "metadata_only"
      t.string :page_locator
      t.timestamps
    end
    add_foreign_key "warehouse.institution_document_assets", "warehouse.institution_releases"
    add_index "warehouse.institution_document_assets",
      [ :institution_release_id, :institution_document_id, :content_sha256 ], unique: true,
      name: "idx_institution_document_assets_unique"
    add_index "warehouse.institution_document_assets", [ :institution_release_id, :content_sha256 ],
      name: "idx_institution_document_assets_sha256"
    add_index "warehouse.institution_document_assets", [ :institution_release_id, :institution_document_id ],
      unique: true, where: "preferred", name: "idx_institution_document_assets_preferred"
    add_check_constraint "warehouse.institution_document_assets",
      "content_sha256 ~ '^[0-9a-f]{64}$'", name: "institution_document_assets_sha256"
    add_check_constraint "warehouse.institution_document_assets",
      "asset_role IN ('final','draft','amended','part','container','unknown')",
      name: "institution_document_assets_role"
    add_check_constraint "warehouse.institution_document_assets",
      "rights_status IN ('redistributable','metadata_only','restricted','unknown')",
      name: "institution_document_assets_rights_status"
    add_check_constraint "warehouse.institution_document_assets", "byte_size >= 0",
      name: "institution_document_assets_byte_size"
    add_check_constraint "warehouse.institution_document_assets",
      "archive_path LIKE 'sha256/%' AND position('..' in archive_path) = 0",
      name: "institution_document_assets_archive_path"
    add_check_constraint "warehouse.institution_document_assets",
      "(asset_role = 'part' AND part_index > 0) OR (asset_role <> 'part' AND part_index IS NULL)",
      name: "institution_document_assets_part_index"
    add_check_constraint "warehouse.institution_document_assets",
      "part_count IS NULL OR (part_count > 0 AND part_index IS NOT NULL AND part_count >= part_index)",
      name: "institution_document_assets_part_count"
  end

  def add_release_consistency_foreign_keys
    execute <<~SQL
      ALTER TABLE warehouse.institutions
        ADD CONSTRAINT fk_institutions_source_release
        FOREIGN KEY (institution_release_id, institution_source_id)
        REFERENCES warehouse.institution_sources (institution_release_id, id);

      ALTER TABLE warehouse.institution_identifiers
        ADD CONSTRAINT fk_institution_identifiers_institution_release
        FOREIGN KEY (institution_release_id, institution_id)
        REFERENCES warehouse.institutions (institution_release_id, id),
        ADD CONSTRAINT fk_institution_identifiers_source_release
        FOREIGN KEY (institution_release_id, institution_source_id)
        REFERENCES warehouse.institution_sources (institution_release_id, id);

      ALTER TABLE warehouse.institution_relationships
        ADD CONSTRAINT fk_institution_relationships_source_institution_release
        FOREIGN KEY (institution_release_id, source_institution_id)
        REFERENCES warehouse.institutions (institution_release_id, id),
        ADD CONSTRAINT fk_institution_relationships_target_institution_release
        FOREIGN KEY (institution_release_id, target_institution_id)
        REFERENCES warehouse.institutions (institution_release_id, id),
        ADD CONSTRAINT fk_institution_relationships_source_release
        FOREIGN KEY (institution_release_id, institution_source_id)
        REFERENCES warehouse.institution_sources (institution_release_id, id);

      ALTER TABLE warehouse.institution_geographies
        ADD CONSTRAINT fk_institution_geographies_institution_release
        FOREIGN KEY (institution_release_id, institution_id)
        REFERENCES warehouse.institutions (institution_release_id, id),
        ADD CONSTRAINT fk_institution_geographies_geography_release
        FOREIGN KEY (institution_release_id, institution_geography_snapshot_id)
        REFERENCES warehouse.institution_geography_snapshots (institution_release_id, id),
        ADD CONSTRAINT fk_institution_geographies_source_release
        FOREIGN KEY (institution_release_id, institution_source_id)
        REFERENCES warehouse.institution_sources (institution_release_id, id);

      ALTER TABLE warehouse.institution_documents
        ADD CONSTRAINT fk_institution_documents_institution_release
        FOREIGN KEY (institution_release_id, institution_id)
        REFERENCES warehouse.institutions (institution_release_id, id),
        ADD CONSTRAINT fk_institution_documents_source_release
        FOREIGN KEY (institution_release_id, institution_source_id)
        REFERENCES warehouse.institution_sources (institution_release_id, id);

      ALTER TABLE warehouse.institution_document_assets
        ADD CONSTRAINT fk_institution_document_assets_document_release
        FOREIGN KEY (institution_release_id, institution_document_id)
        REFERENCES warehouse.institution_documents (institution_release_id, id);
    SQL
  end
end
