module Table
  module Interactions
    class CreateTable < Shared::BaseInteraction
      def initialize(table_repo: Persistence::Postgres::TableRepository.new)
        @table_repo = table_repo
      end

      def call(format:, host_session_id:, host_display_name:, name: nil, max_seats: 4)
        validated = step validate(
          CreateTableContract,
          format: format, max_seats: max_seats, host_display_name: host_display_name, name: name
        )

        table = step create_table(validated, host_session_id)
        seat = step add_host_seat(table, host_session_id, validated[:host_display_name])

        Success(table: table, seat: seat)
      end

      private

      def create_table(validated, host_session_id)
        table = @table_repo.create(
          name: validated[:name],
          format: validated[:format],
          max_seats: validated[:max_seats],
          host_session_id: host_session_id,
          settings: { "starting_life" => starting_life_for(validated[:format]) }
        )
        table.persisted? ? Success(table) : Failure[:persistence_error, table.errors.to_hash]
      end

      def add_host_seat(table, host_session_id, display_name)
        seat = @table_repo.add_seat(table, seat_number: 1, session_id: host_session_id, display_name: display_name)
        seat.persisted? ? Success(seat) : Failure[:persistence_error, seat.errors.to_hash]
      end

      def starting_life_for(format) = format == "commander" ? 40 : 20
    end
  end
end
