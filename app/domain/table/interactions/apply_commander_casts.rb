module Table
  module Interactions
    # Corrects how many times a commander was cast from the command zone (counted on
    # every move out of it, see CardMovement) — after a misplaced drag, say. Only the
    # commander's owner can, and it never goes below zero.
    class ApplyCommanderCasts < BaseGameMutation
      TAX_PER_CAST = 2

      def call(table_slug:, seat_id:, commander_instance_id:, delta:)
        delta = delta.to_i
        return Failure[:validation_error, "A contagem precisa mudar em pelo menos 1"] if delta.zero?

        step apply(table_slug) { |state| adjust(state, seat_id.to_s, commander_instance_id.to_s, delta) }
      end

      private

      def adjust(state, actor_id, commander_id, delta)
        holder_id, = state.locate(commander_id)
        commander = holder_id && state.seat(holder_id).instances[commander_id]
        return Failure[:validation_error, "Essa carta não é um comandante"] unless commander&.commander
        return Failure[:forbidden, "Só o dono do comandante pode corrigir o imposto"] unless commander.owner_seat_id == actor_id

        total = [ commander.command_casts + delta, 0 ].max
        return Success(state) if total == commander.command_casts

        holder = state.seat(holder_id)
        new_state = state.with_seat(holder_id, holder.with_instance(commander_id, commander.with(command_casts: total)))
        Success(append_log(new_state, seat_id: actor_id, event_type: "commander_casts", payload: {
          "card_id" => commander.card_id, "total" => total, "tax" => total * TAX_PER_CAST
        }))
      end
    end
  end
end
