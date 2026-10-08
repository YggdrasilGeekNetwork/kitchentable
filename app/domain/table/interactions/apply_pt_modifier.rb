module Table
  module Interactions
    # Adjusts a battlefield card's power and/or toughness by hand (pump spells, -X/-X
    # effects...). Reset when the card leaves the battlefield.
    class ApplyPtModifier < BaseGameMutation
      def call(table_slug:, seat_id:, card_instance_id:, power: 0, toughness: 0)
        step apply(table_slug) { |state| modify(state, seat_id.to_s, card_instance_id, power.to_i, toughness.to_i) }
      end

      private

      def modify(state, actor_id, instance_id, power, toughness)
        holder_id, zone = state.locate(instance_id)
        return Failure[:not_found, "Card instance not found"] unless holder_id
        return Failure[:validation_error, "Only battlefield cards have power and toughness"] unless zone == "battlefield"

        holder = state.seat(holder_id)
        instance = holder.instances[instance_id]
        changed = instance.with(power_mod: instance.power_mod + power, toughness_mod: instance.toughness_mod + toughness)
        new_state = state.with_seat(holder_id, holder.with_instance(instance_id, changed))
        Success(append_log(new_state, seat_id: actor_id, event_type: "pt_modifier",
                           payload: { "card_id" => public_card_id(instance, zone), "power" => power, "toughness" => toughness }))
      end
    end
  end
end
