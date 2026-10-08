class CreateGameTables < ActiveRecord::Migration[8.0]
  def change
    create_table :game_tables do |t|
      t.string :slug, null: false
      t.string :name
      t.string :format, null: false
      t.integer :status, null: false, default: 0
      t.string :host_session_id, null: false
      t.integer :max_seats, null: false
      t.jsonb :settings, null: false, default: {}
      t.datetime :last_activity_at, null: false

      t.timestamps
    end

    add_index :game_tables, :slug, unique: true
    add_index :game_tables, :last_activity_at
  end
end
