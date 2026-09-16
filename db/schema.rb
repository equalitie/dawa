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

ActiveRecord::Schema[8.1].define(version: 2026_07_23_223552) do
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

  create_table "link_keys", force: :cascade do |t|
    t.date "expires_on"
    t.binary "key", limit: 32
  end

  create_table "links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.datetime "expires_at"
    t.string "label"
    t.integer "linkable_id"
    t.string "linkable_type"
    t.integer "max_uses"
    t.integer "role"
    t.string "type"
    t.datetime "updated_at", null: false
    t.integer "used_count"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "attempt_id"
    t.datetime "created_at", null: false
    t.binary "data"
    t.integer "link_id"
    t.string "session_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["session_id"], name: "index_sessions_on_session_id", unique: true
  end

  create_table "user_attempts", force: :cascade do |t|
    t.json "cleartext_data", default: {}
    t.datetime "created_at"
    t.integer "credential_id"
    t.json "encrypted_data", default: {}
    t.boolean "is_success", default: false
    t.integer "user_id"
  end

  create_table "user_credentials", force: :cascade do |t|
    t.string "authenticator"
    t.string "authenticator_id"
    t.datetime "created_at", null: false
    t.json "data", default: {}
    t.datetime "expires_at"
    t.boolean "is_active", default: false
    t.string "name"
    t.string "type"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.binary "vault"
    t.binary "vault_public_key", limit: 32
    t.binary "vault_seed", limit: 32
    t.index ["user_id"], name: "index_user_credentials_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_on"
    t.json "data", default: {}
    t.string "display_name"
    t.string "email"
    t.boolean "is_active", default: true
    t.boolean "is_admin", default: false
    t.boolean "is_finalized", default: true
    t.datetime "updated_on"
    t.string "username", limit: 40
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "user_credentials", "users"
end
