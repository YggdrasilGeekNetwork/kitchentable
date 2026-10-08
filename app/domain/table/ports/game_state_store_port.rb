module Table
  module Ports
    # Live, ephemeral game state (life totals, zones, card instances, counters, the
    # recent event log) — one JSON-shaped blob per table. Never touches Postgres.
    class GameStateStorePort
      def fetch(table_slug:)
        raise NotImplementedError
      end

      def save(table_slug:, state:)
        raise NotImplementedError
      end

      def delete(table_slug:)
        raise NotImplementedError
      end
    end
  end
end
