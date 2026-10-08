module Table
  module Interactions
    # Takes a card out of the game entirely (a mistaken token, a card added by
    # accident) — unlike exile, it's gone from every zone.
    class ApplyRemoveCard < BaseGameMutation
      def call(table_slug:, seat_id:, card_instance_id:)
        step apply(table_slug) { |state| remove(state, seat_id.to_s, card_instance_id) }
      end

      private

      def remove(state, actor_id, instance_id)
        holder_id, zone = state.locate(instance_id)
        return Failure[:not_found, "Card instance not found"] unless holder_id
        return Failure[:forbidden, "You can't remove that card"] unless touchable?(state, actor_id, holder_id, zone, instance_id)

        instance = state.seat(holder_id).instances[instance_id]
        new_state = state.with_seat(holder_id, state.seat(holder_id).without_card(instance_id))
        Success(append_log(new_state, seat_id: actor_id, event_type: "remove_card",
                           payload: { "card_id" => public_card_id(instance, zone), "from_zone" => zone }))
      end
    end
  end
end
