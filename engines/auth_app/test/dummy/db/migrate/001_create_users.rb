class CreateUsers < ActiveRecord::Migration[8.0]
  def change

    create_table "users" do |t|
      t.string   "username",       limit: 40
      t.string   "email"
      t.datetime "created_on"
      t.datetime "updated_on"
      t.boolean  "is_active",      default: true
      t.json     "data",           default: {}
      t.index ["username"], name: "index_users_on_username", unique: true
    end

    create_table "user_credentials" do |t|
      t.belongs_to :user,          null: false, foreign_key: true
      t.timestamps
      t.string   "type"
      t.string   "name"
      t.boolean  "is_active",        default: false
      t.string   "authenticator"
      t.string   "authenticator_id"
      t.binary   "vault"
      t.binary   "vault_public_key", limit: 32
      t.binary   "vault_seed",       limit: 32
      t.datetime "expires_at"
      t.json     "data",             default: {}
    end

    create_table "user_attempts" do |t|
      t.integer  "user_id"
      t.integer  "credential_id"
      t.datetime "created_at"
      t.boolean  "is_success",     default: false
      t.json     "encrypted_data", default: {}
      t.json     "cleartext_data", default: {}
    end

  end
end
