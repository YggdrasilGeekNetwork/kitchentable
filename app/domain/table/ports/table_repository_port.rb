module Table
  module Ports
    # Durable "general representation of the session" — which tables/seats exist.
    # Never stores live game state (life, zones, counters) — that's GameStateStorePort.
    class TableRepositoryPort
      def find_by_slug(slug)
        raise NotImplementedError
      end

      def create(attrs)
        raise NotImplementedError
      end

      def add_seat(table, attrs)
        raise NotImplementedError
      end

      def seats_for(table)
        raise NotImplementedError
      end

      # Yields inside a row-level lock on the table record. Used as a cheap mutex to
      # serialize concurrent mutations to the same table's Redis game state — the lock
      # guards the critical section, it never stores the payload itself.
      def with_lock(table, &block)
        raise NotImplementedError
      end
    end
  end
end
