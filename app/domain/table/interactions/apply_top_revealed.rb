module Table
  module Interactions
    # Playing with the top card of your library revealed (Future Sight, Courser of
    # Kruphix...): everyone sees it, and you can play it straight from there.
    class ApplyTopRevealed < BaseGameMutation
      def call(table_slug:, seat_id:, revealed:)
        step apply(table_slug) { |state| toggle(state, seat_id.to_s, revealed) }
      end

      private

      def toggle(state, seat_id, revealed)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state

        new_state = state.with_seat(seat_id, seat_state.with(top_revealed: revealed))
        Success(append_log(new_state, seat_id: seat_id, event_type: "top_revealed", payload: { "revealed" => revealed }))
      end
    end
  end
end
