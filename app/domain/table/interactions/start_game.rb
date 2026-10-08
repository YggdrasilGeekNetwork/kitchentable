module Table
  module Interactions
    # Deals a validated deck into a seat's ephemeral zones (see SeatState.deal) and
    # remembers the deck for restarts. The first seat to be dealt in becomes the
    # active player.
    class StartGame < BaseGameMutation
      def call(table_slug:, seat_id:, validated_deck:)
        deck = {
          "format" => validated_deck.format,
          "library" => validated_deck.library_card_ids,
          "command" => validated_deck.command_card_ids
        }
        step apply(table_slug) { |state| deal(state, seat_id.to_s, deck) }
      end

      private

      def deal(state, seat_id, deck)
        seat_state = Entities::SeatState.deal(seat_id: seat_id, deck: deck)
        new_state = state.with_seat(seat_id, seat_state)
        new_state = new_state.with(active_seat_id: seat_id, first_seat_id: seat_id) unless new_state.active_seat_id
        Success(append_log(new_state, seat_id: seat_id, event_type: "start_game",
                           payload: { "library_size" => seat_state.zones["library"].size }))
      end
    end
  end
end
