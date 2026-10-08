module Table
  module Interactions
    # Shows cards from the player's own hidden zones (hand, or library cards they're
    # peeking at) to everyone, until they end the reveal or the cards move.
    class ApplyReveal < BaseGameMutation
      MAX_CARDS = 100

      def call(table_slug:, seat_id:, card_instance_ids:)
        ids = Array(card_instance_ids).map(&:to_s).uniq
        return Failure[:validation_error, "Choose 1-#{MAX_CARDS} cards to reveal"] unless ids.size.between?(1, MAX_CARDS)

        step apply(table_slug) { |state| reveal(state, seat_id.to_s, ids) }
      end

      private

      def reveal(state, actor_id, ids)
        locations = ids.map { |id| state.locate(id) }
        return Failure[:not_found, "Card instance not found"] if locations.any?(&:nil?)

        owners = locations.map(&:first).uniq
        return Failure[:validation_error, "Reveal cards from one player at a time"] unless owners.one?
        unless ids.zip(locations).all? { |id, (holder, zone)| touchable?(state, actor_id, holder, zone, id) }
          return Failure[:forbidden, "You can't reveal those cards"]
        end

        reveal = { "id" => SecureRandom.hex(4), "by_seat_id" => actor_id, "owner_seat_id" => owners.first, "card_instance_ids" => ids }
        new_state = state.with(reveals: state.reveals + [ reveal ])
        Success(append_log(new_state, seat_id: actor_id, event_type: "reveal",
                           payload: { "owner_seat_id" => owners.first, "count" => ids.size }))
      end
    end
  end
end
