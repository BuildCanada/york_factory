# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_23_190045) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "business_establishments", force: :cascade do |t|
    t.string "address"
    t.string "business_name", null: false
    t.string "business_number"
    t.string "city"
    t.bigint "corporate_entity_id"
    t.datetime "created_at", null: false
    t.string "employee_size_range"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.string "naics_code"
    t.string "naics_description"
    t.string "postal_code"
    t.string "province", null: false
    t.jsonb "raw_data", default: {}
    t.bigint "raw_ingestion_id"
    t.string "source_system", default: "odbiz"
    t.bigint "standardized_address_id"
    t.string "trade_name"
    t.datetime "updated_at", null: false
    t.index ["business_name"], name: "index_business_establishments_on_business_name"
    t.index ["business_number"], name: "idx_biz_est_bn_unique", unique: true, where: "(business_number IS NOT NULL)"
    t.index ["business_number"], name: "index_business_establishments_on_business_number"
    t.index ["corporate_entity_id"], name: "index_business_establishments_on_corporate_entity_id"
    t.index ["naics_code"], name: "index_business_establishments_on_naics_code"
    t.index ["postal_code"], name: "index_business_establishments_on_postal_code"
    t.index ["province"], name: "index_business_establishments_on_province"
    t.index ["raw_ingestion_id"], name: "index_business_establishments_on_raw_ingestion_id"
    t.index ["standardized_address_id"], name: "index_business_establishments_on_standardized_address_id"
  end

  create_table "corporate_directors", force: :cascade do |t|
    t.string "address"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "full_name", null: false
    t.boolean "is_resident_canadian"
    t.string "normalized_name", null: false
    t.string "postal_code"
    t.string "province"
    t.datetime "updated_at", null: false
    t.index ["normalized_name", "postal_code"], name: "idx_directors_name_postal"
    t.index ["normalized_name"], name: "index_corporate_directors_on_normalized_name"
  end

  create_table "corporate_entities", force: :cascade do |t|
    t.string "business_activity"
    t.string "business_number"
    t.string "corporation_type"
    t.datetime "created_at", null: false
    t.date "dissolution_date"
    t.boolean "enriched", default: false
    t.datetime "enriched_at"
    t.string "governing_act"
    t.bigint "government_entity_id"
    t.date "incorporation_date"
    t.string "jurisdiction", null: false
    t.string "legal_name", null: false
    t.boolean "needs_review", default: false
    t.jsonb "raw_data", default: {}
    t.bigint "raw_ingestion_id"
    t.string "registered_office_address"
    t.string "registered_office_postal_code"
    t.string "registered_office_province"
    t.string "registry_id", null: false
    t.string "source_system"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["business_number"], name: "index_corporate_entities_on_business_number"
    t.index ["enriched"], name: "index_corporate_entities_on_enriched"
    t.index ["government_entity_id"], name: "index_corporate_entities_on_government_entity_id"
    t.index ["jurisdiction", "registry_id"], name: "index_corporate_entities_on_jurisdiction_and_registry_id", unique: true
    t.index ["jurisdiction"], name: "index_corporate_entities_on_jurisdiction"
    t.index ["legal_name"], name: "idx_corp_entities_legal_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["legal_name"], name: "index_corporate_entities_on_legal_name"
    t.index ["needs_review"], name: "index_corporate_entities_on_needs_review"
    t.index ["raw_ingestion_id"], name: "index_corporate_entities_on_raw_ingestion_id"
    t.index ["registered_office_province"], name: "index_corporate_entities_on_registered_office_province"
    t.index ["source_system"], name: "index_corporate_entities_on_source_system"
    t.index ["status"], name: "index_corporate_entities_on_status"
  end

  create_table "corporate_entity_aliases", force: :cascade do |t|
    t.string "alias_name", null: false
    t.bigint "corporate_entity_id", null: false
    t.datetime "created_at", null: false
    t.date "effective_date"
    t.date "expiry_date"
    t.datetime "updated_at", null: false
    t.index ["alias_name"], name: "index_corporate_entity_aliases_on_alias_name"
    t.index ["corporate_entity_id", "alias_name"], name: "idx_corp_alias_entity_name", unique: true
    t.index ["corporate_entity_id"], name: "index_corporate_entity_aliases_on_corporate_entity_id"
  end

  create_table "corporate_registrations", force: :cascade do |t|
    t.bigint "corporate_entity_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "details", default: {}
    t.date "event_date"
    t.string "event_type", null: false
    t.datetime "updated_at", null: false
    t.index ["corporate_entity_id", "event_type", "event_date"], name: "idx_registrations_entity_event"
    t.index ["corporate_entity_id"], name: "index_corporate_registrations_on_corporate_entity_id"
  end

  create_table "director_appointments", force: :cascade do |t|
    t.date "appointed_date"
    t.date "ceased_date"
    t.bigint "corporate_director_id", null: false
    t.bigint "corporate_entity_id", null: false
    t.datetime "created_at", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["corporate_director_id"], name: "index_director_appointments_on_corporate_director_id"
    t.index ["corporate_entity_id", "corporate_director_id"], name: "idx_appointments_entity_director", unique: true
    t.index ["corporate_entity_id"], name: "index_director_appointments_on_corporate_entity_id"
  end

  create_table "fiscal_authorities", force: :cascade do |t|
    t.decimal "amount", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.text "description"
    t.string "document_type", null: false
    t.string "fiscal_year", null: false
    t.bigint "government_entity_id", null: false
    t.bigint "lineage_entry_id"
    t.bigint "raw_ingestion_id"
    t.datetime "updated_at", null: false
    t.string "vote_number"
    t.string "vote_type", null: false
    t.index ["government_entity_id", "fiscal_year", "document_type", "vote_number"], name: "idx_fiscal_authorities_unique", unique: true
    t.index ["government_entity_id"], name: "index_fiscal_authorities_on_government_entity_id"
    t.index ["lineage_entry_id"], name: "index_fiscal_authorities_on_lineage_entry_id"
    t.index ["raw_ingestion_id"], name: "index_fiscal_authorities_on_raw_ingestion_id"
  end

  create_table "fiscal_expenditures", force: :cascade do |t|
    t.decimal "actual_expenditure", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.text "description"
    t.string "fiscal_year", null: false
    t.bigint "government_entity_id", null: false
    t.bigint "lineage_entry_id"
    t.decimal "pa_voted_ceiling", precision: 15, scale: 2
    t.bigint "raw_ingestion_id"
    t.datetime "updated_at", null: false
    t.string "vote_number"
    t.string "vote_type", null: false
    t.index ["government_entity_id", "fiscal_year", "vote_number"], name: "idx_fiscal_expenditures_unique", unique: true
    t.index ["government_entity_id"], name: "index_fiscal_expenditures_on_government_entity_id"
    t.index ["lineage_entry_id"], name: "index_fiscal_expenditures_on_lineage_entry_id"
    t.index ["raw_ingestion_id"], name: "index_fiscal_expenditures_on_raw_ingestion_id"
  end

  create_table "government_entities", force: :cascade do |t|
    t.string "canonical_name", null: false
    t.datetime "created_at", null: false
    t.boolean "needs_review", default: false, null: false
    t.integer "org_id_infobase"
    t.datetime "updated_at", null: false
    t.index ["canonical_name"], name: "index_government_entities_on_canonical_name", unique: true
    t.index ["org_id_infobase"], name: "index_government_entities_on_org_id_infobase", unique: true, where: "(org_id_infobase IS NOT NULL)"
  end

  create_table "government_entity_aliases", force: :cascade do |t|
    t.string "alias_name", null: false
    t.datetime "created_at", null: false
    t.bigint "government_entity_id", null: false
    t.datetime "updated_at", null: false
    t.date "valid_from"
    t.date "valid_to"
    t.index ["alias_name", "valid_from"], name: "index_government_entity_aliases_on_alias_name_and_valid_from", unique: true
    t.index ["government_entity_id"], name: "index_government_entity_aliases_on_government_entity_id"
  end

  create_table "lineage_entries", force: :cascade do |t|
    t.decimal "confidence", precision: 5, scale: 4
    t.datetime "created_at", null: false
    t.boolean "human_override", default: false
    t.string "llm_model"
    t.jsonb "llm_prompt_snapshot"
    t.jsonb "llm_response_snapshot"
    t.datetime "override_at"
    t.string "override_by"
    t.bigint "raw_ingestion_id"
    t.string "source_field"
    t.string "source_value"
    t.string "target_field"
    t.string "target_value"
    t.string "transformation_type", null: false
    t.datetime "updated_at", null: false
    t.index ["raw_ingestion_id"], name: "index_lineage_entries_on_raw_ingestion_id"
  end

  create_table "lobbying_activities", force: :cascade do |t|
    t.string "client_name"
    t.datetime "created_at", null: false
    t.date "end_date"
    t.bigint "government_entity_id"
    t.bigint "lineage_entry_id"
    t.bigint "lobbyist_id", null: false
    t.bigint "raw_ingestion_id"
    t.date "start_date"
    t.string "status"
    t.string "subject_matter"
    t.datetime "updated_at", null: false
    t.index ["government_entity_id"], name: "index_lobbying_activities_on_government_entity_id"
    t.index ["lineage_entry_id"], name: "index_lobbying_activities_on_lineage_entry_id"
    t.index ["lobbyist_id"], name: "index_lobbying_activities_on_lobbyist_id"
    t.index ["raw_ingestion_id"], name: "index_lobbying_activities_on_raw_ingestion_id"
  end

  create_table "lobbyists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "lobbyist_type"
    t.string "name", null: false
    t.string "registration_number"
    t.datetime "updated_at", null: false
    t.index ["registration_number"], name: "index_lobbyists_on_registration_number", unique: true, where: "(registration_number IS NOT NULL)"
  end

  create_table "raw_ingestions", force: :cascade do |t|
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "fetched_at", null: false
    t.string "raw_file_path", null: false
    t.jsonb "scraping_progress", default: {}
    t.bigint "source_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["source_id", "checksum"], name: "index_raw_ingestions_on_source_id_and_checksum", unique: true
    t.index ["source_id"], name: "index_raw_ingestions_on_source_id"
  end

  create_table "sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "fetch_frequency"
    t.string "format", null: false
    t.datetime "last_fetched_at"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["name"], name: "index_sources_on_name", unique: true
  end

  create_table "standard_object_expenditures", force: :cascade do |t|
    t.decimal "amount", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.string "fiscal_year", null: false
    t.bigint "government_entity_id", null: false
    t.bigint "raw_ingestion_id"
    t.string "standard_object", null: false
    t.datetime "updated_at", null: false
    t.index ["government_entity_id", "fiscal_year", "standard_object"], name: "idx_std_obj_expenditures_unique", unique: true
    t.index ["government_entity_id"], name: "index_standard_object_expenditures_on_government_entity_id"
    t.index ["raw_ingestion_id"], name: "index_standard_object_expenditures_on_raw_ingestion_id"
  end

  create_table "standardized_addresses", force: :cascade do |t|
    t.string "census_subdivision_name"
    t.string "census_subdivision_type"
    t.string "city", null: false
    t.string "country", default: "CA"
    t.datetime "created_at", null: false
    t.string "full_address", null: false
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.string "postal_code", null: false
    t.string "province", null: false
    t.bigint "raw_ingestion_id"
    t.string "source_id"
    t.string "street_name"
    t.string "street_number"
    t.string "unit_number"
    t.datetime "updated_at", null: false
    t.index ["city"], name: "index_standardized_addresses_on_city"
    t.index ["latitude", "longitude"], name: "idx_addresses_lat_lon"
    t.index ["postal_code", "street_name"], name: "idx_addresses_postal_street"
    t.index ["postal_code"], name: "index_standardized_addresses_on_postal_code"
    t.index ["province"], name: "index_standardized_addresses_on_province"
    t.index ["raw_ingestion_id"], name: "index_standardized_addresses_on_raw_ingestion_id"
    t.index ["source_id"], name: "index_standardized_addresses_on_source_id", unique: true
  end

  add_foreign_key "business_establishments", "corporate_entities"
  add_foreign_key "business_establishments", "raw_ingestions"
  add_foreign_key "business_establishments", "standardized_addresses"
  add_foreign_key "corporate_entities", "government_entities"
  add_foreign_key "corporate_entities", "raw_ingestions"
  add_foreign_key "corporate_entity_aliases", "corporate_entities"
  add_foreign_key "corporate_registrations", "corporate_entities"
  add_foreign_key "director_appointments", "corporate_directors"
  add_foreign_key "director_appointments", "corporate_entities"
  add_foreign_key "fiscal_authorities", "government_entities"
  add_foreign_key "fiscal_authorities", "lineage_entries"
  add_foreign_key "fiscal_authorities", "raw_ingestions"
  add_foreign_key "fiscal_expenditures", "government_entities"
  add_foreign_key "fiscal_expenditures", "lineage_entries"
  add_foreign_key "fiscal_expenditures", "raw_ingestions"
  add_foreign_key "government_entity_aliases", "government_entities"
  add_foreign_key "lineage_entries", "raw_ingestions"
  add_foreign_key "lobbying_activities", "government_entities"
  add_foreign_key "lobbying_activities", "lineage_entries"
  add_foreign_key "lobbying_activities", "lobbyists"
  add_foreign_key "lobbying_activities", "raw_ingestions"
  add_foreign_key "raw_ingestions", "sources"
  add_foreign_key "standard_object_expenditures", "government_entities"
  add_foreign_key "standard_object_expenditures", "raw_ingestions"
  add_foreign_key "standardized_addresses", "raw_ingestions"
end
