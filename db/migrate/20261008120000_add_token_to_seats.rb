class AddTokenToSeats < ActiveRecord::Migration[8.0]
  # A secret per seat, carried in the table URL (?seat=...) so a player can get back
  # to their seat from any browser even if cookies are lost.
  def up
    add_column :seats, :token, :string
    execute "UPDATE seats SET token = md5(random()::text || id::text || clock_timestamp()::text)"
    change_column_null :seats, :token, false
    add_index :seats, :token, unique: true
  end

  def down
    remove_index :seats, :token
    remove_column :seats, :token
  end
end
