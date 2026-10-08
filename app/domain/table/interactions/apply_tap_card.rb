module Table
  module Interactions
    # Taps or untaps a permanent on any battlefield (players self-enforce who may).
    class ApplyTapCard < BaseGameMutation
      def call(table_slug:, seat_id:, card_instance_id:, tapped:)
        step apply(table_slug) { |state| tap_card(state, seat_id.to_s, card_instance_id, tapped) }
      end

      private

      def tap_card(state, actor_id, instance_id, tapped)
        holder_id, zone = state.locate(instance_id)
        return Failure[:not_found, "Card instance not found"] unless holder_id
        return Failure[:validation_error, "Only permanents on the battlefield can be tapped"] unless zone == "battlefield"

        holder = state.seat(holder_id)
        instance = holder.instances[instance_id]
        new_state = state.with_seat(holder_id, holder.with_instance(instance_id, instance.with_tapped(tapped)))
        Success(append_log(new_state, seat_id: actor_id, event_type: "tap_card",
                           payload: { "card_id" => public_card_id(instance, zone), "tapped" => tapped }))
      end
    end
  end
end
