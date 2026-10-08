module CardCatalog
  module Interactions
    # Name search for the board's "add a card / token" picker.
    class SearchCards < Shared::BaseInteraction
      MIN_LENGTH = 2

      def initialize(catalog: Persistence::Postgres::CardCatalogRepository.new)
        @catalog = catalog
      end

      def call(query:)
        query = query.to_s.strip
        return Success([]) if query.length < MIN_LENGTH

        Success(@catalog.search(query).map { |card| { "id" => card.id, "name" => card.name, "type_line" => card.type_line } })
      end
    end
  end
end
