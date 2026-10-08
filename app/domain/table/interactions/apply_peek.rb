module Table
  module Interactions
    # Lets a player privately look at the top `count` cards of a library — their own
    # (scry, surveil, "look at the top N") or another seat's — or, with `search: true`,
    # their whole library (tutors, fetching a land). Everyone is told what they're
    # doing; only they see the cards, and they can then move them (to hand, the bottom,
    # another zone, or reordered on top). A search shows every card for as long as it
    # lasts. What was revealed is a fixed set of cards (see SeatState#peek).
    class ApplyPeek < BaseGameMutation
      MAX_COUNT = 100

      def call(table_slug:, seat_id:, count: nil, target_seat_id: nil, search: false)
        target_id = (target_seat_id.presence || seat_id).to_s
        if search
          return Failure[:forbidden, "You can only search your own library"] unless target_id == seat_id.to_s
        else
          count = count.to_i
          return Failure[:validation_error, "Look at between 1 and #{MAX_COUNT} cards"] unless count.between?(1, MAX_COUNT)
        end

        step apply(table_slug) { |state| peek(state, seat_id.to_s, target_id, search ? nil : count) }
      end

      private

      def peek(state, actor_id, target_id, count)
        actor = state.seat(actor_id)
        return Failure[:not_found, "Seat has no game state yet"] unless actor && state.seat(target_id)

        library = state.seat(target_id).zones["library"]
        ids = count ? library.first(count) : library
        new_state = state.with_seat(actor_id, actor.with(peek: { "seat_id" => target_id, "card_instance_ids" => ids, "search" => count.nil? }))
        event = count.nil? ? [ "library_search", {} ] : [ "peek", { "target_seat_id" => target_id, "count" => count } ]
        Success(append_log(new_state, seat_id: actor_id, event_type: event[0], payload: event[1]))
      end
    end
  end
end
