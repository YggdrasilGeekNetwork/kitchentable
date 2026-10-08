module Fakes
  # In-memory double for CardCatalog::Ports::CardCatalogPort — avoids needing real
  # Scryfall-synced Card rows in the test database for interaction/validator tests.
  class FakeCardCatalog < CardCatalog::Ports::CardCatalogPort
    FakeCard = Struct.new(:id, :name, :type_line, :color_identity, :legalities, :image_uris, :card_faces,
                          :mana_cost, :oracle_text, :power, :toughness, :loyalty, keyword_init: true) do
      def legal_in?(format) = legalities.fetch(format.to_s, "legal") == "legal"
    end

    def initialize
      @cards_by_normalized_name = {}
      @next_id = 1
    end

    def register(name:, type_line: "Creature", color_identity: [], legalities: {}, image_uris: {}, card_faces: [], **stats)
      normalized = name.downcase.gsub(/[^a-z0-9]/, "")
      card = FakeCard.new(id: @next_id, name: name, type_line: type_line, color_identity: color_identity, legalities: legalities,
                          image_uris: image_uris, card_faces: card_faces, **stats)
      @next_id += 1
      @cards_by_normalized_name[normalized] = card
      card
    end

    def find_by_name(name)
      @cards_by_normalized_name[name.downcase.gsub(/[^a-z0-9]/, "")]
    end

    def find_many(ids) = @cards_by_normalized_name.values.select { |c| ids.include?(c.id) }.index_by(&:id)

    def search(query, limit: 12)
      @cards_by_normalized_name.values.select { |c| c.name.downcase.include?(query.downcase) }.first(limit)
    end

    # Fake: link a card to the tokens it makes with `link_tokens(card, token...)`.
    def link_tokens(card, *tokens) = (@tokens_by_card ||= {})[card.id] = tokens

    def deck_tokens(card_ids) = card_ids.uniq.flat_map { |id| (@tokens_by_card || {}).fetch(id, []) }.uniq(&:id).sort_by(&:name)

    def legal?(card:, format:) = card.legal_in?(format)

    def upsert_bulk(_card_attrs_list) = raise NotImplementedError, "not needed by current tests"
  end
end
