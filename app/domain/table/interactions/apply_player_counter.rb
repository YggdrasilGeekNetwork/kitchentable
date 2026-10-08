module Table
  module Interactions
    # Free-form player counters (poison, energy, experience...), on the player's own
    # seat or another's. Adding one makes it show on that player's bar, where it stays
    # (even at zero) until removed with `remove: true`.
    class ApplyPlayerCounter < BaseGameMutation
      MAX_KEY_LENGTH = 40

      def call(table_slug:, seat_id:, key:, delta: 0, target_seat_id: nil, remove: false)
        key = key.to_s.strip
        return Failure[:validation_error, "Counter name must be 1-#{MAX_KEY_LENGTH} characters"] unless key.length.between?(1, MAX_KEY_LENGTH)

        target_id = (target_seat_id.presence || seat_id).to_s
        step apply(table_slug) { |state| adjust(state, seat_id.to_s, target_id, key, delta.to_i, remove) }
      end

      private

      def adjust(state, actor_id, target_id, key, delta, remove)
        target = state.seat(target_id)
        return Failure[:not_found, "Seat has no game state yet"] unless target

        updated = remove ? target.without_counter(key) : target.with_counter(key, delta)
        new_state = state.with_seat(target_id, updated)
        Success(append_log(new_state, seat_id: actor_id, event_type: "player_counter",
                           payload: { "target_seat_id" => target_id, "key" => key, "delta" => delta, "removed" => remove,
                                      "value" => updated.counters.fetch(key, 0) }))
      end
    end
  end
end
