module Table
  module Interactions
    # Passes the turn to the next dealt-in seat (by seat order), wrapping around. The
    # turn counter goes up on every pass. Only the player whose turn it is can pass it.
    # The player whose turn begins loses summoning sickness on what they control. When the
    # turn comes back around to the player who opened the game, a new round begins.
    class ApplyPassTurn < BaseGameMutation
      def call(table_slug:, seat_id:)
        table = table_repo.find_by_slug(table_slug)
        return Failure[:not_found, "Table not found"] unless table

        order = table_repo.seats_for(table).sort_by(&:seat_number).map { |s| s.id.to_s }
        step apply(table_slug) { |state| pass(state, seat_id.to_s, order) }
      end

      private

      def pass(state, actor_id, order)
        playing = order.select { |id| state.seat(id) }
        return Failure[:not_found, "Nobody has been dealt in yet"] if playing.empty?
        if playing.include?(state.active_seat_id) && state.active_seat_id != actor_id
          return Failure[:forbidden, "Only the player whose turn it is can pass it"]
        end

        current = playing.index(state.active_seat_id) || -1
        next_id = playing[(current + 1) % playing.size]
        first = playing.include?(state.first_seat_id) ? state.first_seat_id : playing.first
        new_round = next_id == first
        new_state = state.with(active_seat_id: next_id, turn_number: state.turn_number + 1, turn_started: false,
                               first_seat_id: first, round: new_round ? state.round + 1 : state.round)
        new_state = new_state.with_seat(next_id, without_sickness(new_state.seat(next_id)))
        Success(append_log(new_state, seat_id: actor_id, event_type: "pass_turn",
                           payload: { "active_seat_id" => next_id, "round" => new_state.round, "new_round" => new_round }))
      end
    end
  end
end
