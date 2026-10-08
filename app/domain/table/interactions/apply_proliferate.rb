module Table
  module Interactions
    # "Proliferate all": one more of each kind of counter already on every permanent
    # the player controls, and on the player.
    class ApplyProliferate < BaseGameMutation
      def call(table_slug:, seat_id:)
        step apply(table_slug) { |state| proliferate(state, seat_id.to_s) }
      end

      private

      def proliferate(state, seat_id)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state

        grown = seat_state.zones["battlefield"].filter_map { |id|
          instance = seat_state.instances[id]
          [ id, instance.counters.keys.reduce(instance) { |i, key| i.with_counter(key, 1) } ] if instance.counters.any?
        }.to_h
        new_seat_state = seat_state.with_instances(seat_state.instances.merge(grown))
        new_seat_state = seat_state.counters.select { |_, n| n.positive? }.keys.reduce(new_seat_state) { |s, key| s.with_counter(key, 1) }

        new_state = state.with_seat(seat_id, new_seat_state)
        Success(append_log(new_state, seat_id: seat_id, event_type: "proliferate", payload: { "permanents" => grown.size }))
      end
    end
  end
end
