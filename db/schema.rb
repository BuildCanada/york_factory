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

ActiveRecord::Schema[8.1].define(version: 2026_03_26_200001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "builders", force: :cascade do |t|
    t.text "byline_en"
    t.text "byline_fr"
    t.datetime "created_at", null: false
    t.datetime "published_at"
    t.text "quote_en"
    t.text "quote_fr"
    t.string "slug", null: false
    t.string "title_en"
    t.string "title_fr"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_builders_on_slug", unique: true
  end

  create_table "faqs", force: :cascade do |t|
    t.text "answer_text_en"
    t.text "answer_text_fr"
    t.datetime "created_at", null: false
    t.string "link_href"
    t.string "link_text"
    t.integer "position", default: 0
    t.datetime "published_at"
    t.text "question_en"
    t.text "question_fr"
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_faqs_on_position"
  end

  create_table "feed_items", force: :cascade do |t|
    t.string "author"
    t.datetime "created_at", null: false
    t.text "embed_code"
    t.boolean "featured", default: false
    t.string "item_type", null: false
    t.datetime "published_at"
    t.string "source_url", null: false
    t.string "subtitle_en"
    t.string "subtitle_fr"
    t.string "tags", default: [], array: true
    t.string "title_en"
    t.string "title_fr"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["featured"], name: "index_feed_items_on_featured"
    t.index ["item_type"], name: "index_feed_items_on_item_type"
    t.index ["source_url"], name: "index_feed_items_on_source_url", unique: true
    t.index ["tags"], name: "index_feed_items_on_tags", using: :gin
  end

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

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.datetime "created_at"
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "jwt_denylists", force: :cascade do |t|
    t.datetime "exp", null: false
    t.string "jti", null: false
    t.index ["jti"], name: "index_jwt_denylists_on_jti"
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

  create_table "memos", force: :cascade do |t|
    t.string "author_avatar"
    t.bigint "author_id"
    t.string "author_name"
    t.string "author_title"
    t.string "category"
    t.bigint "co_author_id"
    t.datetime "created_at", null: false
    t.boolean "featured", default: false
    t.jsonb "key_messages_en", default: []
    t.jsonb "key_messages_fr", default: []
    t.datetime "published_at"
    t.string "slug", null: false
    t.string "title_en"
    t.string "title_fr"
    t.text "twitter_embed"
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_memos_on_author_id"
    t.index ["category"], name: "index_memos_on_category"
    t.index ["co_author_id"], name: "index_memos_on_co_author_id"
    t.index ["featured"], name: "index_memos_on_featured"
    t.index ["published_at"], name: "index_memos_on_published_at"
    t.index ["slug"], name: "index_memos_on_slug", unique: true
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

  create_table "posts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "hidden", default: false
    t.datetime "published_at"
    t.string "slug", null: false
    t.text "summary_en"
    t.text "summary_fr"
    t.string "title_en"
    t.string "title_fr"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_posts_on_slug", unique: true
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

  create_table "subscribers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "postal_code"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_subscribers_on_email", unique: true
  end

  create_table "team_members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "linkedin_url"
    t.string "name", null: false
    t.integer "position", default: 0
    t.datetime "published_at"
    t.string "role"
    t.string "slug"
    t.string "title_en"
    t.string "title_fr"
    t.string "twitter_url"
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_team_members_on_position"
    t.index ["role"], name: "index_team_members_on_role"
    t.index ["slug"], name: "index_team_members_on_slug", unique: true
  end

  create_table "testimonials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0
    t.datetime "published_at"
    t.text "quote_en"
    t.text "quote_fr"
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_testimonials_on_position"
  end

  create_table "tools", force: :cascade do |t|
    t.string "accent_color"
    t.datetime "created_at", null: false
    t.boolean "featured", default: false
    t.integer "position", default: 0
    t.datetime "published_at"
    t.string "size", default: "small"
    t.string "slug", null: false
    t.string "title_en"
    t.string "title_fr"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["slug"], name: "index_tools_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "name"
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
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
  add_foreign_key "memos", "team_members", column: "author_id"
  add_foreign_key "memos", "team_members", column: "co_author_id"
  add_foreign_key "organization_aliases", "organizations"
  add_foreign_key "raw_ingestions", "sources"
  add_foreign_key "standard_object_expenditures", "organizations"
  add_foreign_key "standard_object_expenditures", "raw_ingestions"
end
