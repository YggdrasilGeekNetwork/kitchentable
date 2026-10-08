module Table
  module Interactions
    class JoinTable < Shared::BaseInteraction
      def initialize(table_repo: Persistence::Postgres::TableRepository.new)
        @table_repo = table_repo
      end

      def call(table_slug:, session_id:, display_name:)
        validated = step validate(JoinTableContract, table_slug: table_slug, display_name: display_name)

        table = step find_table(validated[:table_slug])
        step check_capacity(table)
        seat = step add_seat(table, session_id, validated[:display_name])

        Success(table: table, seat: seat)
      end

      private

      def find_table(slug)
        table = @table_repo.find_by_slug(slug)
        table ? Success(table) : Failure[:not_found, "Table not found"]
      end

      def check_capacity(table)
        current = @table_repo.seats_for(table).size
        current < table.max_seats ? Success(table) : Failure[:table_full, "Table is full"]
      end

      def add_seat(table, session_id, display_name)
        next_number = @table_repo.seats_for(table).size + 1
        seat = @table_repo.add_seat(table, seat_number: next_number, session_id: session_id, display_name: display_name)
        seat.persisted? ? Success(seat) : Failure[:persistence_error, seat.errors.to_hash]
      end
    end
  end
end
