module Table
  module Interactions
    # Ends the opening-hand decision: no more mulligans for this player.
    class ApplyKeepHand < BaseGameMutation
      def call(table_slug:, seat_id:)
        step apply(table_slug) { |state| keep(state, seat_id.to_s) }
      end

      private

      def keep(state, seat_id)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Esse jogador ainda não enviou um deck"] unless seat_state
        return Failure[:validation_error, "Você já manteve a sua mão"] if seat_state.hand_kept

        new_state = state.with_seat(seat_id, seat_state.with(hand_kept: true))
        Success(append_log(new_state, seat_id: seat_id, event_type: "keep_hand",
                           payload: { "hand_size" => seat_state.zones["hand"].size, "mulligan_count" => seat_state.mulligan_count }))
      end
    end
  end
end
