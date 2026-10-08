class AddRelatedTokensToCards < ActiveRecord::Migration[8.0]
  # Tokens (and emblems) a card can make, from Scryfall's all_parts:
  # [{ "name", "type_line" }]. Used to suggest the tokens a deck can create.
  def change
    add_column :cards, :related_tokens, :jsonb, default: [], null: false
  end
end
