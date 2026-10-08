module Table
  module Interactions
    # Ties the pasted decklist text (plus, for Commander, the separately chosen
    # commander or Partner/Background pair), parsing + format validation, and dealing the result into the seat's
    # ephemeral zones into one use case. Nothing here is persisted — a re-submission
    # simply redeals the seat.
    class SubmitDecklist < Shared::BaseInteraction
      def initialize(table_repo: Persistence::Postgres::TableRepository.new)
        @table_repo = table_repo
      end

      def call(table_slug:, seat_id:, format:, raw_text:, commander_names: [])
        validated = step validate(SubmitDecklistContract, format: format)
        table = step find_table(table_slug)
        seat = step find_seat(table, seat_id)
        validated_deck = step Interactions::ValidateDecklist.call(
          raw_text: raw_text, format: validated[:format], commander_names: commander_names
        )
        new_state = step Interactions::StartGame.call(table_slug: table_slug, seat_id: seat.id.to_s, validated_deck: validated_deck)

        Success(state: new_state)
      end

      private

      def find_table(slug)
        table = @table_repo.find_by_slug(slug)
        table ? Success(table) : Failure[:not_found, "Table not found"]
      end

      def find_seat(table, seat_id)
        seat = @table_repo.seats_for(table).find { |s| s.id == seat_id.to_i }
        seat ? Success(seat) : Failure[:not_found, "Seat not found"]
      end
    end
  end
end
