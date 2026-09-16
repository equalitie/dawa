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

ActiveRecord::Schema[8.1].define(version: 3) do
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
    t.integer "membership_id"
    t.integer "role"
    t.string "type"
    t.datetime "updated_at", null: false
    t.integer "used_count"
    t.integer "workspace_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "attempt_id"
    t.datetime "created_at", null: false
    t.binary "data"
    t.string "session_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "link_id"
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
    t.string "email"
    t.boolean "is_active", default: true
    t.datetime "updated_on"
    t.string "username", limit: 40
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "user_credentials", "users"
end
