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

ActiveRecord::Schema[8.1].define(version: 2026_03_23_081911) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "fiscal_authorities", force: :cascade do |t|
    t.decimal "amount", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.text "description"
    t.string "document_type", null: false
    t.string "fiscal_year", null: false
    t.bigint "lineage_entry_id"
    t.bigint "organization_id", null: false
    t.bigint "raw_ingestion_id"
    t.datetime "updated_at", null: false
    t.string "vote_number"
    t.string "vote_type", null: false
    t.index ["lineage_entry_id"], name: "index_fiscal_authorities_on_lineage_entry_id"
    t.index ["organization_id", "fiscal_year", "document_type", "vote_number"], name: "idx_fiscal_authorities_unique", unique: true
    t.index ["organization_id"], name: "index_fiscal_authorities_on_organization_id"
    t.index ["raw_ingestion_id"], name: "index_fiscal_authorities_on_raw_ingestion_id"
  end

  create_table "fiscal_expenditures", force: :cascade do |t|
    t.decimal "actual_expenditure", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.text "description"
    t.string "fiscal_year", null: false
    t.bigint "lineage_entry_id"
    t.bigint "organization_id", null: false
    t.decimal "pa_voted_ceiling", precision: 15, scale: 2
    t.bigint "raw_ingestion_id"
    t.datetime "updated_at", null: false
    t.string "vote_number"
    t.string "vote_type", null: false
    t.index ["lineage_entry_id"], name: "index_fiscal_expenditures_on_lineage_entry_id"
    t.index ["organization_id", "fiscal_year", "vote_number"], name: "idx_fiscal_expenditures_unique", unique: true
    t.index ["organization_id"], name: "index_fiscal_expenditures_on_organization_id"
    t.index ["raw_ingestion_id"], name: "index_fiscal_expenditures_on_raw_ingestion_id"
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
    t.bigint "lineage_entry_id"
    t.bigint "lobbyist_id", null: false
    t.bigint "organization_id"
    t.bigint "raw_ingestion_id"
    t.date "start_date"
    t.string "status"
    t.string "subject_matter"
    t.datetime "updated_at", null: false
    t.index ["lineage_entry_id"], name: "index_lobbying_activities_on_lineage_entry_id"
    t.index ["lobbyist_id"], name: "index_lobbying_activities_on_lobbyist_id"
    t.index ["organization_id"], name: "index_lobbying_activities_on_organization_id"
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

  create_table "organization_aliases", force: :cascade do |t|
    t.string "alias_name", null: false
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.date "valid_from"
    t.date "valid_to"
    t.index ["alias_name", "valid_from"], name: "index_organization_aliases_on_alias_name_and_valid_from", unique: true
    t.index ["organization_id"], name: "index_organization_aliases_on_organization_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "canonical_name", null: false
    t.datetime "created_at", null: false
    t.boolean "needs_review", default: false, null: false
    t.integer "org_id_infobase"
    t.datetime "updated_at", null: false
    t.index ["canonical_name"], name: "index_organizations_on_canonical_name", unique: true
    t.index ["org_id_infobase"], name: "index_organizations_on_org_id_infobase", unique: true, where: "(org_id_infobase IS NOT NULL)"
  end

  create_table "raw_ingestions", force: :cascade do |t|
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "fetched_at", null: false
    t.string "raw_file_path", null: false
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
    t.bigint "organization_id", null: false
    t.bigint "raw_ingestion_id"
    t.string "standard_object", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "fiscal_year", "standard_object"], name: "idx_std_obj_expenditures_unique", unique: true
    t.index ["organization_id"], name: "index_standard_object_expenditures_on_organization_id"
    t.index ["raw_ingestion_id"], name: "index_standard_object_expenditures_on_raw_ingestion_id"
  end

  add_foreign_key "fiscal_authorities", "lineage_entries"
  add_foreign_key "fiscal_authorities", "organizations"
  add_foreign_key "fiscal_authorities", "raw_ingestions"
  add_foreign_key "fiscal_expenditures", "lineage_entries"
  add_foreign_key "fiscal_expenditures", "organizations"
  add_foreign_key "fiscal_expenditures", "raw_ingestions"
  add_foreign_key "lineage_entries", "raw_ingestions"
  add_foreign_key "lobbying_activities", "lineage_entries"
  add_foreign_key "lobbying_activities", "lobbyists"
  add_foreign_key "lobbying_activities", "organizations"
  add_foreign_key "lobbying_activities", "raw_ingestions"
  add_foreign_key "organization_aliases", "organizations"
  add_foreign_key "raw_ingestions", "sources"
  add_foreign_key "standard_object_expenditures", "organizations"
  add_foreign_key "standard_object_expenditures", "raw_ingestions"
end
