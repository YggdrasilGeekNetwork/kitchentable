module Persistence
  module Postgres
    class TableRepository < Table::Ports::TableRepositoryPort
      def find_by_slug(slug)
        ::GameTable.find_by(slug: slug)
      end

      # Returns the record regardless of whether save succeeded — callers (Interactions)
      # decide Success/Failure by checking #persisted?/#errors, same convention as
      # arkheion_api's interactions operating on plain ActiveRecord objects.
      def create(attrs)
        ::GameTable.new(attrs).tap(&:save)
      end

      def add_seat(table, attrs)
        table.seats.new(attrs).tap(&:save)
      end

      def seats_for(table)
        table.seats.order(:seat_number).to_a
      end

      def with_lock(table, &block)
        table.with_lock { block.call }
      end
    end
  end
end
