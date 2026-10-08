module Table
  module Interactions
    # Draws `count` cards from the top of the player's library (fewer if it runs out).
    class ApplyDraw < BaseGameMutation
      MAX_COUNT = 30

      def call(table_slug:, seat_id:, count: 1)
        count = count.to_i
        return Failure[:validation_error, "Draw between 1 and #{MAX_COUNT} cards"] unless count.between?(1, MAX_COUNT)

        step apply(table_slug) { |state| draw(state, seat_id.to_s, count) }
      end

      private

      def draw(state, seat_id, count)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state

        drawn = seat_state.zones["library"].first(count)
        zones = seat_state.zones.merge(
          "library" => seat_state.zones["library"].drop(drawn.size), "hand" => seat_state.zones["hand"] + drawn
        )
        new_state = state.with_seat(seat_id, seat_state.with_zones(zones))
        Success(append_log(new_state, seat_id: seat_id, event_type: "draw", payload: { "count" => drawn.size }))
      end
    end
  end
end
