module Table
  module Interactions
    # Untap, clear summoning sickness and draw, by hand — for extra turns or
    # goldfishing. The turn button uses ApplyStartTurn, which also tracks whose turn it is.
    class ApplyNewTurn < BaseGameMutation
      def call(table_slug:, seat_id:)
        step apply(table_slug) { |state| new_turn(state, seat_id.to_s) }
      end

      private

      def new_turn(state, seat_id)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state

        new_seat_state, drew = begin_turn(seat_state)
        Success(append_log(state.with_seat(seat_id, new_seat_state), seat_id: seat_id, event_type: "new_turn", payload: { "drew" => drew }))
      end
    end
  end
end
