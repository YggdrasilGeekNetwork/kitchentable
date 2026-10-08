module Table
  module Interactions
    # Turns a multi-face card in a public zone to its other face (transform, MDFC).
    class ApplyFlipCard < BaseGameMutation
      def call(table_slug:, seat_id:, card_instance_id:)
        step apply(table_slug) { |state| flip(state, seat_id.to_s, card_instance_id) }
      end

      private

      def flip(state, actor_id, instance_id)
        holder_id, zone = state.locate(instance_id)
        return Failure[:not_found, "Card instance not found"] unless holder_id
        return Failure[:validation_error, "Only cards in public zones can be flipped"] unless Entities::SeatState::PUBLIC_ZONES.include?(zone)

        holder = state.seat(holder_id)
        instance = holder.instances[instance_id]
        flipped = instance.with(face_index: instance.face_index.zero? ? 1 : 0)
        new_state = state.with_seat(holder_id, holder.with_instance(instance_id, flipped))
        Success(append_log(new_state, seat_id: actor_id, event_type: "flip_card",
                           payload: { "card_id" => public_card_id(instance, zone), "face_index" => flipped.face_index }))
      end
    end
  end
end
