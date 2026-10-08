module Table
  module Interactions
    # Moves several selected cards to one zone at once, all or nothing, in one update.
    # `moves` is [{ "card_instance_id", "x", "y" }] in selection order: cards sent to
    # the bottom of a library keep that order, and cards sent to the top end up with
    # the first one on top. See CardMovement for where cards can go.
    class ApplyCardMoves < BaseGameMutation
      include CardMovement

      MAX_CARDS = 100

      def call(table_slug:, seat_id:, moves:, to_zone:, to_position: nil, to_seat_id: nil)
        moves = Array(moves).map { |m| m.to_h.transform_keys(&:to_s) }
        return Failure[:validation_error, "Unknown zone: #{to_zone}"] unless Entities::SeatState::ZONES.include?(to_zone)
        return Failure[:validation_error, "Move 1-#{MAX_CARDS} cards"] unless moves.size.between?(1, MAX_CARDS)

        ordered = to_position.to_i.zero? && !to_position.nil? ? moves.reverse : moves
        step apply(table_slug) { |state| move_all(state, seat_id.to_s, ordered, to_zone, to_position, to_seat_id.presence&.to_s) }
      end

      private

      def move_all(state, actor_id, moves, to_zone, to_position, to_seat_id)
        moves.reduce(Success(state)) do |result, move|
          result.bind do |current|
            move_card(current, actor_id, move["card_instance_id"].to_s, to_zone, to_position, to_seat_id, move["x"], move["y"])
          end
        end
      end
    end
  end
end
