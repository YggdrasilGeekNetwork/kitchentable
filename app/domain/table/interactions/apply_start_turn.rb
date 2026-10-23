module Table
  module Interactions
    # The active player starts the turn they were passed: untap, clear summoning
    # sickness, draw. Anyone else can take a turn out of order (`out_of_turn: true`,
    # after confirming on screen) — they become the active player — but only once the
    # game is under way: the first turn belongs to the first player.
    class ApplyStartTurn < BaseGameMutation
      def call(table_slug:, seat_id:, out_of_turn: false)
        step apply(table_slug) { |state| start(state, seat_id.to_s, out_of_turn) }
      end

      private

      def start(state, seat_id, out_of_turn)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Esse jogador ainda não enviou um deck"] unless seat_state

        my_turn = state.active_seat_id == seat_id
        return Failure[:validation_error, "Seu turno já começou"] if my_turn && state.turn_started
        return Failure[:forbidden, "Não é a sua vez"] if !my_turn && !out_of_turn
        return Failure[:forbidden, "O primeiro jogador ainda não começou a partida"] if !my_turn && state.awaiting_first_turn?

        new_seat_state, drew = begin_turn(seat_state)
        new_seat_state = new_seat_state.with(turns_taken: seat_state.turns_taken + 1)
        new_state = state.with_seat(seat_id, new_seat_state).with(
          active_seat_id: seat_id, turn_started: true, turn_number: my_turn ? state.turn_number : state.turn_number + 1
        )
        Success(append_log(new_state, seat_id: seat_id, event_type: "start_turn",
                           payload: { "out_of_turn" => !my_turn, "drew" => drew, "seat_turn" => new_seat_state.turns_taken }))
      end
    end
  end
end
