module Table
  module Interactions
    # The tokens a seat's deck can make, to suggest when creating tokens. From the deck
    # it was dealt, or — for seats dealt before decks were remembered — the cards it
    # owns.
    class FetchDeckTokens < Shared::BaseInteraction
      def initialize(
        state_store: Persistence::Redis::GameStateStore.new,
        card_catalog: Persistence::Postgres::CardCatalogRepository.new
      )
        @state_store = state_store
        @card_catalog = card_catalog
      end

      def call(table_slug:, seat_id:)
        seat_state = @state_store.fetch(table_slug: table_slug).seat(seat_id)
        return Success([]) unless seat_state

        card_ids = seat_state.deck ? seat_state.deck.values_at("library", "command").flatten : owned_card_ids(seat_state, seat_id)
        Success(@card_catalog.deck_tokens(card_ids).map { |token|
          { "id" => token.id, "name" => token.name, "type_line" => token.type_line, "power" => token.power, "toughness" => token.toughness }
        })
      end

      private

      def owned_card_ids(seat_state, seat_id)
        seat_state.instances.values.reject(&:token).select { |i| (i.owner_seat_id || seat_id.to_s) == seat_id.to_s }.map(&:card_id).compact
      end
    end
  end
end
