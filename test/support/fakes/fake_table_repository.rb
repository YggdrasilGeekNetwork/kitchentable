module Fakes
  # In-memory double for Table::Ports::TableRepositoryPort — used so interaction unit
  # tests never need a real Postgres connection or GameTable/Seat fixtures.
  class FakeTableRepository < Table::Ports::TableRepositoryPort
    def initialize
      @tables = {}
    end

    def register(table) = @tables[table.slug] = table

    def find_by_slug(slug) = @tables[slug]

    def with_lock(_table, &block) = block.call

    def seats_for(table) = table.seats

    def create(attrs) = raise NotImplementedError, "stub in a specific test if needed"
    def add_seat(table, attrs) = raise NotImplementedError, "stub in a specific test if needed"
  end
end
