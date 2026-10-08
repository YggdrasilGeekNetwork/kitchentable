module Table
  module Interactions
    class ApplyShuffle < BaseGameMutation
      def call(table_slug:, seat_id:)
        step apply(table_slug) { |state| shuffle(state, seat_id.to_s) }
      end

      private

      def shuffle(state, seat_id)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state

        zones = seat_state.zones.merge("library" => seat_state.zones["library"].shuffle)
        new_state = state.with_seat(seat_id, seat_state.with_zones(zones)).without_peeks_into(seat_id)
        Success(append_log(new_state, seat_id: seat_id, event_type: "shuffle"))
      end
    end
  end
end
