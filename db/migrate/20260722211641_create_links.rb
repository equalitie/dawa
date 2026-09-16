class CreateLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :links do |t|
      t.timestamps
      t.string :type
      t.integer :linkable_id
      t.string :linkable_type
      t.integer :created_by_id
      t.string :label
      t.datetime :expires_at
      t.integer :max_uses
      t.integer :used_count
      t.integer :role
    end

    create_table :link_keys do |t|
      t.date :expires_on
      t.binary :key, limit: 32
    end
  end
end
