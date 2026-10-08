class AddStatsToCards < ActiveRecord::Migration[8.0]
  # Strings, not integers: Scryfall uses values like "*", "1+*" and "X".
  def change
    add_column :cards, :power, :string
    add_column :cards, :toughness, :string
    add_column :cards, :loyalty, :string
  end
end
