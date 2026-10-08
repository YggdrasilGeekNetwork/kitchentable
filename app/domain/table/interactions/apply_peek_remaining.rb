module Table
  module Interactions
    # Puts the revealed cards nobody has moved yet back on the top or bottom of their
    # library, in random order, and ends the reveal ("put the rest on the bottom in a
    # random order").
    class ApplyPeekRemaining < BaseGameMutation
      PLACEMENTS = %w[top bottom].freeze

      def call(table_slug:, seat_id:, placement:)
        placement = placement.to_s
        return Failure[:validation_error, "Place them on top or bottom"] unless PLACEMENTS.include?(placement)

        step apply(table_slug) { |state| place(state, seat_id.to_s, placement) }
      end

      private

      def place(state, actor_id, placement)
        peek = state.seat(actor_id)&.peek
        return Failure[:not_found, "Nothing revealed from a library"] unless peek

        owner_id = peek["seat_id"].to_s
        owner = state.seat(owner_id)
        library = owner.zones["library"]
        rest = (peek["card_instance_ids"].to_a & library).shuffle
        others = library - rest
        reordered = placement == "top" ? rest + others : others + rest

        new_state = state.with_seat(owner_id, owner.with_zones(owner.zones.merge("library" => reordered)))
        new_state = new_state.with_seat(actor_id, new_state.seat(actor_id).with(peek: nil))
        Success(append_log(new_state, seat_id: actor_id, event_type: "peek_remaining",
                           payload: { "target_seat_id" => owner_id, "count" => rest.size, "placement" => placement }))
      end
    end
  end
end
