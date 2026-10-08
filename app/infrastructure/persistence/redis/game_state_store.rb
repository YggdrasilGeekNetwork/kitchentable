module Persistence
  module Redis
    class GameStateStore < Table::Ports::GameStateStorePort
      KEY_PREFIX = "kitchentable:table"
      TTL = 12.hours

      def fetch(table_slug:)
        raw = REDIS_POOL.with { |conn| conn.get(key_for(table_slug)) }
        Table::Entities::GameState.from_h(raw ? JSON.parse(raw) : nil)
      end

      def save(table_slug:, state:)
        REDIS_POOL.with { |conn| conn.set(key_for(table_slug), state.to_h.to_json, ex: TTL) }
        state
      end

      def delete(table_slug:)
        REDIS_POOL.with { |conn| conn.del(key_for(table_slug)) }
      end

      private

      def key_for(table_slug) = "#{KEY_PREFIX}:#{table_slug}:state"
    end
  end
end
