module Table
  module Interactions
    # Commander damage a player takes from one commander. It is damage, so it also
    # comes off their life total; lowering it (fixing a mistake) gives the life back.
    # 21 from a single commander is lethal — players see it highlighted and decide.
    class ApplyCommanderDamage < BaseGameMutation
      LETHAL = 21

      def call(table_slug:, seat_id:, commander_instance_id:, delta:, target_seat_id: nil)
        delta = delta.to_i
        return Failure[:validation_error, "Damage must change by a non-zero amount"] if delta.zero?

        target_id = (target_seat_id.presence || seat_id).to_s
        step apply(table_slug) { |state| damage(state, seat_id.to_s, target_id, commander_instance_id.to_s, delta) }
      end

      private

      def damage(state, actor_id, target_id, commander_id, delta)
        target = state.seat(target_id)
        return Failure[:not_found, "Seat has no game state yet"] unless target

        holder_id, = state.locate(commander_id)
        commander = holder_id && state.seat(holder_id).instances[commander_id]
        return Failure[:validation_error, "That card isn't a commander"] unless commander&.commander

        current = target.commander_damage.fetch(commander_id, 0)
        applied = [ delta, -current ].max # can't go below zero damage
        return Success(state) if applied.zero?

        damage = target.commander_damage.merge(commander_id => current + applied)
        new_target = target.with(commander_damage: damage, life_total: target.life_total - applied)
        new_state = state.with_seat(target_id, new_target)
        Success(append_log(new_state, seat_id: actor_id, event_type: "commander_damage", payload: {
          "target_seat_id" => target_id, "card_id" => commander.card_id, "delta" => applied,
          "total" => current + applied, "life_total" => new_target.life_total, "lethal" => current + applied >= LETHAL
        }))
      end
    end
  end
end
