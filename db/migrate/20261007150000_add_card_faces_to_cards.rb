class AddCardFacesToCards < ActiveRecord::Migration[8.0]
  def up
    # Multi-face cards (transform, modal DFC, adventure, split...) are named after all
    # their faces ("Elesh Norn // The Argent Etchings") and, for double-faced ones,
    # carry their images per face rather than at the top level.
    add_column :cards, :front_face_name_normalized, :string
    add_column :cards, :card_faces, :jsonb, default: [], null: false
    add_index :cards, :front_face_name_normalized

    # Printings sold under a different name ("Godzilla, King of the Monsters" for
    # Zilortha, Secret Lair Universes Beyond names...) — Scryfall's `flavor_name`.
    add_column :cards, :alternate_names_normalized, :string, array: true, default: [], null: false
    add_index :cards, :alternate_names_normalized, using: :gin

    # Same normalization as the importer, applied to the part before " // ", so
    # name lookups work without a re-sync. `card_faces` fills in on the next sync.
    execute <<~SQL
      UPDATE cards
      SET front_face_name_normalized = regexp_replace(lower(split_part(name, ' // ', 1)), '[^a-z0-9]', '', 'g')
    SQL
  end

  def down
    remove_index :cards, :alternate_names_normalized
    remove_column :cards, :alternate_names_normalized
    remove_index :cards, :front_face_name_normalized
    remove_column :cards, :card_faces
    remove_column :cards, :front_face_name_normalized
  end
end
