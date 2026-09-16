# 20250822000000
class CreateSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :sessions, if_not_exists: true  do |t|
      t.string :session_id, :null => false
      t.binary :data
      t.timestamps
      t.integer :user_id
      t.integer :attempt_id
      t.index :session_id, :unique => true
    end
  end
end
