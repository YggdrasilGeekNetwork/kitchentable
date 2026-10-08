module Table
  module Interactions
    # Adjusts a life total — the player's own by default, or another seat's
    # (`target_seat_id`) for drains and damage, which players self-enforce.
    class ApplyLifeChange < BaseGameMutation
      def call(table_slug:, seat_id:, delta:, target_seat_id: nil)
        target_id = (target_seat_id.presence || seat_id).to_s
        step apply(table_slug) { |state| change_life(state, seat_id.to_s, target_id, delta.to_i) }
      end

      private

      def change_life(state, actor_id, target_id, delta)
        target = state.seat(target_id)
        return Failure[:not_found, "Seat has no game state yet"] unless target

        new_state = state.with_seat(target_id, target.with_life_total(target.life_total + delta))
        Success(append_log(new_state, seat_id: actor_id, event_type: "life_change",
                           payload: { "target_seat_id" => target_id, "delta" => delta, "life_total" => target.life_total + delta }))
      end
    end
  end
end
