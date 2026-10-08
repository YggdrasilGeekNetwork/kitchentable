module Table
  module Interactions
    # London mulligan: shuffle hand back into library and draw a fresh 7. Only while
    # the opening hand hasn't been kept. Once they keep, the player puts cards on the
    # bottom themselves (dragging them to the library's bottom) — `mulligan_count`
    # shows everyone how many they owe.
    class ApplyMulligan < BaseGameMutation
      HAND_SIZE = 7

      def call(table_slug:, seat_id:)
        step apply(table_slug) { |state| mulligan(state, seat_id.to_s) }
      end

      private

      def mulligan(state, seat_id)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state
        return Failure[:validation_error, "You already kept your hand"] if seat_state.hand_kept

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
