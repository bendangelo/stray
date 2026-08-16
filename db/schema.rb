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

ActiveRecord::Schema[8.1].define(version: 2026_08_16_175852) do
  create_table "data_migrations", primary_key: "version", id: :string, force: :cascade do |t|
  end

  create_table "follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "source_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.float "weight", default: 1.0
    t.index ["source_id"], name: "index_follows_on_source_id"
    t.index ["user_id", "source_id"], name: "index_follows_on_user_id_and_source_id", unique: true
    t.index ["user_id"], name: "index_follows_on_user_id"
  end

  create_table "full_search_index_versions", primary_key: "table_name", id: :text, force: :cascade do |t|
    t.text "config_hash", null: false
    t.datetime "rebuilt_at", precision: nil, null: false
  end

  create_table "items", force: :cascade do |t|
    t.text "content_html"
    t.text "content_text"
    t.datetime "created_at", null: false
    t.integer "duration"
    t.binary "embedding"
    t.string "external_id", null: false
    t.datetime "fetched_at"
    t.datetime "published_at"
    t.integer "source_id", null: false
    t.integer "state", default: 0
    t.text "summary"
    t.string "thumbnail_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.integer "user_id", null: false
    t.index ["source_id", "external_id"], name: "index_items_on_source_id_and_external_id", unique: true
    t.index ["source_id"], name: "index_items_on_source_id"
    t.index ["user_id", "state", "published_at"], name: "index_items_on_user_id_and_state_and_published_at"
    t.index ["user_id"], name: "index_items_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.string "ai_provider_api_key"
    t.string "ai_provider_name", default: "NONE"
    t.string "ai_provider_url"
    t.datetime "created_at", null: false
    t.string "embedding_model"
    t.boolean "embedding_model_present", default: false
    t.string "instance_domain"
    t.string "instance_name"
    t.boolean "llm_tagging_enabled", default: false
    t.string "llm_tagging_model", default: "qwen2.5:1.5b"
    t.string "smtp_host"
    t.string "smtp_password"
    t.integer "smtp_port", default: 587
    t.string "smtp_username"
    t.datetime "updated_at", null: false
    t.float "zero_shot_threshold", default: 0.35
    t.integer "zero_shot_top_n", default: 5
  end

  create_table "sources", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "icon_url"
    t.integer "kind", null: false
    t.string "last_error"
    t.datetime "last_error_at"
    t.datetime "last_polled_at"
    t.string "name"
    t.datetime "next_crawl_at"
    t.integer "poll_interval"
    t.boolean "polling", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.integer "user_id", null: false
    t.index ["next_crawl_at", "active"], name: "index_sources_on_next_crawl_at_and_active", where: "active = true"
    t.index ["user_id", "external_id", "kind"], name: "index_sources_on_user_id_and_external_id_and_kind", unique: true
    t.index ["user_id"], name: "index_sources_on_user_id"
  end

  create_table "taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "item_id", null: false
    t.float "score"
    t.integer "source", default: 0, null: false
    t.integer "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id", "tag_id", "source"], name: "index_taggings_on_item_id_and_tag_id_and_source", unique: true
    t.index ["item_id"], name: "index_taggings_on_item_id"
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.binary "embedding"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "name"], name: "index_tags_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "follows", "sources"
  add_foreign_key "follows", "users"
  add_foreign_key "items", "sources"
  add_foreign_key "items", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "sources", "users"
  add_foreign_key "taggings", "items"
  add_foreign_key "taggings", "tags"
  add_foreign_key "tags", "users"

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
  create_virtual_table "items_fts", "fts5", ["\"title\"", "\"content_text\"", "tokenize='porter'"]
end
