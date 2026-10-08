module Fakes
  # In-memory double for Table::Ports::GameStateStorePort. Round-trips through
  # to_h/from_h just like the real Redis adapter does through JSON, so tests catch
  # serialization bugs (e.g. symbol vs string keys) the same way production would.
  class FakeGameStateStore < Table::Ports::GameStateStorePort
    def initialize
      @states = {}
    end

    def seed(table_slug:, state:) = @states[table_slug] = state

    def fetch(table_slug:)
      Table::Entities::GameState.from_h(@states[table_slug]&.to_h)
    end

    def save(table_slug:, state:)
      @states[table_slug] = state
      state
    end

    def delete(table_slug:) = @states.delete(table_slug)
  end
end
