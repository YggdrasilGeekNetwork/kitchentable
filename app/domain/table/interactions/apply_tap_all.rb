module Table
  module Interactions
    # Taps or untaps every permanent the player controls (untap step, "tap all lands"...).
    class ApplyTapAll < BaseGameMutation
      def call(table_slug:, seat_id:, tapped:)
        step apply(table_slug) { |state| tap_all(state, seat_id.to_s, tapped) }
      end

      private

      def tap_all(state, seat_id, tapped)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state

        new_state = state.with_seat(seat_id, set_tapped(seat_state, tapped))
        Success(append_log(new_state, seat_id: seat_id, event_type: tapped ? "tap_all" : "untap_all"))
      end

      def set_tapped(seat_state, tapped)
        changed = seat_state.zones["battlefield"].to_h { |id| [ id, seat_state.instances[id].with_tapped(tapped) ] }
        seat_state.with_instances(seat_state.instances.merge(changed))
      end
    end
  end
end
