module Table
  module Interactions
    # Turns a battlefield card face down (morph, manifest, disguise) or back face up.
    # While face down, only its controller sees what it is.
    class ApplyFaceDown < BaseGameMutation
      def call(table_slug:, seat_id:, card_instance_id:, face_down:)
        step apply(table_slug) { |state| turn(state, seat_id.to_s, card_instance_id, face_down) }
      end

      private

      def turn(state, actor_id, instance_id, face_down)
        holder_id, zone = state.locate(instance_id)
        return Failure[:not_found, "Card instance not found"] unless holder_id
        return Failure[:validation_error, "Only battlefield cards can be turned face down"] unless zone == "battlefield"

        holder = state.seat(holder_id)
        instance = holder.instances[instance_id].with(face_down: face_down)
        new_state = state.with_seat(holder_id, holder.with_instance(instance_id, instance))
        Success(append_log(new_state, seat_id: actor_id, event_type: "face_down",
                           payload: { "face_down" => face_down, "card_id" => face_down ? nil : instance.card_id }))
      end
    end
  end
end
