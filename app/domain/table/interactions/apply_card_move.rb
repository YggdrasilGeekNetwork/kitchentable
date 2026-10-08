module Table
  module Interactions
    # Moves one card instance — see CardMovement for where cards can go.
    class ApplyCardMove < BaseGameMutation
      include CardMovement

      def call(table_slug:, seat_id:, card_instance_id:, to_zone:, to_position: nil, to_seat_id: nil, x: nil, y: nil)
        unless Entities::SeatState::ZONES.include?(to_zone)
          return Failure[:validation_error, "Unknown zone: #{to_zone}"]
        end

        step apply(table_slug) { |state|
          move_card(state, seat_id.to_s, card_instance_id, to_zone, to_position, to_seat_id.presence&.to_s, x, y)
        }
      end
    end
  end
end
