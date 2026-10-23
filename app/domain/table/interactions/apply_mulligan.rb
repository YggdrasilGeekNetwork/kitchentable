module Table
  module Interactions
    # London mulligan: shuffle hand back into library and draw a fresh 7. Only while
    # the opening hand hasn't been kept. Once they keep, the player puts cards on the
    # bottom themselves (dragging them to the library's bottom), one card per mulligan
    # after the first, which is free — the board enforces it before letting them keep.
    class ApplyMulligan < BaseGameMutation
      HAND_SIZE = 7

      def call(table_slug:, seat_id:)
        step apply(table_slug) { |state| mulligan(state, seat_id.to_s) }
      end

      private

      def mulligan(state, seat_id)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Esse jogador ainda não enviou um deck"] unless seat_state
        return Failure[:validation_error, "Você já manteve a sua mão"] if seat_state.hand_kept

        library = (seat_state.zones["hand"] + seat_state.zones["library"]).shuffle
        hand = library.shift(HAND_SIZE)

        new_seat_state = seat_state
          .with_zones(seat_state.zones.merge("hand" => hand, "library" => library))
          .with_mulligan_count(seat_state.mulligan_count + 1)

        new_state = state.with_seat(seat_id, new_seat_state)
        Success(append_log(new_state, seat_id: seat_id, event_type: "mulligan", payload: { "mulligan_count" => new_seat_state.mulligan_count }))
      end
    end
  end
end
