module Table
  module Interactions
    # Counters on a card in a public zone (+1/+1, loyalty, charge, commander tax...).
    class ApplyCardCounter < BaseGameMutation
      MAX_KEY_LENGTH = 40

      def call(table_slug:, seat_id:, card_instance_id:, key:, delta:)
        key = key.to_s.strip
        return Failure[:validation_error, "Counter name must be 1-#{MAX_KEY_LENGTH} characters"] unless key.length.between?(1, MAX_KEY_LENGTH)

        step apply(table_slug) { |state| adjust(state, seat_id.to_s, card_instance_id, key, delta.to_i) }
      end

      private

      def adjust(state, actor_id, instance_id, key, delta)
        holder_id, zone = state.locate(instance_id)
        return Failure[:not_found, "Card instance not found"] unless holder_id
        unless Entities::SeatState::PUBLIC_ZONES.include?(zone)
          return Failure[:validation_error, "Counters go on cards in public zones"]
        end

        holder = state.seat(holder_id)
        instance = holder.instances[instance_id].with_counter(key, delta)
        new_state = state.with_seat(holder_id, holder.with_instance(instance_id, instance))
        Success(append_log(new_state, seat_id: actor_id, event_type: "card_counter",
                           payload: { "card_id" => public_card_id(instance, zone), "key" => key, "delta" => delta,
                                      "value" => instance.counters.fetch(key, 0) }))
      end
    end
  end
end
