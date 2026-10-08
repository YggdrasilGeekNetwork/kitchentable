module Table
  module Interactions
    # Puts the top `count` cards of the player's library into their graveyard.
    class ApplyMill < BaseGameMutation
      MAX_COUNT = 100

      def call(table_slug:, seat_id:, count: 1)
        count = count.to_i
        return Failure[:validation_error, "Mill between 1 and #{MAX_COUNT} cards"] unless count.between?(1, MAX_COUNT)

        step apply(table_slug) { |state| mill(state, seat_id.to_s, count) }
      end

      private

      def mill(state, seat_id, count)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state

        milled = seat_state.zones["library"].first(count)
        zones = seat_state.zones.merge(
          "library" => seat_state.zones["library"].drop(milled.size), "graveyard" => milled.reverse + seat_state.zones["graveyard"]
        )
        new_state = state.with_seat(seat_id, seat_state.with_zones(zones))
        Success(append_log(new_state, seat_id: seat_id, event_type: "mill", payload: { "count" => milled.size }))
      end
    end
  end
end
