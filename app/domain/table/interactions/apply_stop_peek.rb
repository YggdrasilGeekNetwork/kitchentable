module Table
  module Interactions
    class ApplyStopPeek < BaseGameMutation
      def call(table_slug:, seat_id:)
        step apply(table_slug) { |state| stop(state, seat_id.to_s) }
      end

      private

      def stop(state, seat_id)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state

        Success(state.with_seat(seat_id, seat_state.with(peek: nil)))
      end
    end
  end
end
