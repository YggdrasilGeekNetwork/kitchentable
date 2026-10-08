module Table
  module Interactions
    # Takes summoning sickness off a creature by hand (haste, or a mistake).
    class ApplyRemoveSickness < BaseGameMutation
      def call(table_slug:, seat_id:, card_instance_id:)
        step apply(table_slug) { |state| cure(state, card_instance_id) }
      end

      private

      def cure(state, instance_id)
        holder_id, zone = state.locate(instance_id)
        return Failure[:not_found, "Card instance not found"] unless holder_id && zone == "battlefield"

        holder = state.seat(holder_id)
        Success(state.with_seat(holder_id, holder.with_instance(instance_id, holder.instances[instance_id].with(sick: false))))
      end
    end
  end
end
