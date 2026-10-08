class CreateSeats < ActiveRecord::Migration[8.0]
  def change
    create_table :seats do |t|
      t.references :game_table, null: false, foreign_key: true
      t.integer :seat_number, null: false
      t.string :session_id, null: false
      t.string :display_name, null: false
      t.integer :status, null: false, default: 0
      t.datetime :last_seen_at, null: false

      t.timestamps
    end

    add_index :seats, [ :game_table_id, :seat_number ], unique: true
    add_index :seats, [ :game_table_id, :session_id ], unique: true
  end
end
