module Table
  module Interactions
    # Moving one card instance, shared by single and batch moves (mixed into
    # BaseGameMutation subclasses).
    #
    # A card can go anywhere a player may put it: between their own zones, onto another
    # seat's battlefield (control change), or back from someone else's battlefield.
    # Non-battlefield destinations always belong to the card's owner, so a stolen
    # creature that dies goes to its owner's graveyard. Tokens that leave the
    # battlefield cease to exist. `to_position` orders the destination (-1 = bottom);
    # without one, piles (library, graveyard, exile — index 0 is the top) get the card
    # on top and hand/command zone at the end. `x`/`y` place a card on the battlefield.
    # A creature arriving under a new controller (cast, put onto the battlefield, or
    # stolen) gets summoning sickness.
    module CardMovement
      include Dry::Monads[:result] # Failure[...] is looked up lexically, from this module

      PILES = %w[library graveyard exile].freeze

      private

      def move_card(state, actor_id, instance_id, to_zone, to_position, to_seat_id, x, y)
        holder_id, from_zone = state.locate(instance_id)
        return Failure[:not_found, "Card instance not found"] unless holder_id
        return Failure[:forbidden, "You can't move that card"] unless touchable?(state, actor_id, holder_id, from_zone, instance_id)

        instance = state.seat(holder_id).instances[instance_id]
        destination_id = to_zone == "battlefield" ? (to_seat_id || actor_id) : (instance.owner_seat_id || holder_id)
        return Failure[:not_found, "Seat has no game state yet"] unless state.seat(destination_id)

        repositioning = from_zone == "battlefield" && to_zone == "battlefield" && holder_id == destination_id
        moved = from_zone == "battlefield" && to_zone != "battlefield" ? instance.leaving_battlefield : instance
        moved = moved.with(x: x.to_f, y: y.to_f) if to_zone == "battlefield" && x && y
        if to_zone == "battlefield" && !repositioning && creature?(instance)
          moved = moved.with(sick: true)
        end

        new_state = state.without_peeked(instance_id)
        new_state = new_state.with_seat(holder_id, new_state.seat(holder_id).without_card(instance_id))
        unless instance.token && to_zone != "battlefield"
          position = to_position.nil? ? (PILES.include?(to_zone) ? 0 : nil) : to_position.to_i
          new_state = new_state.with_seat(destination_id, new_state.seat(destination_id).with_card(instance_id, moved, zone: to_zone, position: position))
        end
        return Success(new_state) if repositioning

        Success(append_log(new_state, seat_id: actor_id, event_type: "move_card", payload: {
          "card_id" => public_card_id(instance, from_zone, to_zone),
          "from_seat_id" => holder_id, "from_zone" => from_zone,
          "to_seat_id" => destination_id, "to_zone" => to_zone,
          "to_bottom" => to_zone == "library" && to_position.to_i.negative?
        }))
      end
    end
  end
end
