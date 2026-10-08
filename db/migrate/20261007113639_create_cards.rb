class CreateCards < ActiveRecord::Migration[8.0]
  def change
    create_table :cards do |t|
      t.uuid :scryfall_oracle_id, null: false
      t.string :name, null: false
      t.string :name_normalized, null: false
      t.string :mana_cost
      t.decimal :cmc
      t.string :type_line
      t.text :oracle_text
      t.jsonb :colors, null: false, default: []
      t.jsonb :color_identity, null: false, default: []
      t.jsonb :legalities, null: false, default: {}
      t.jsonb :image_uris, null: false, default: {}
      t.string :layout
      t.string :set_code
      t.string :collector_number
      t.string :rarity

      t.timestamps
    end

    add_index :cards, :scryfall_oracle_id, unique: true
    add_index :cards, :name_normalized
  end
end
