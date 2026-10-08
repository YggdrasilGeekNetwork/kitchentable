module Table
  module Interactions
    # The current table as one seat may see it — sent when a player (re)connects, so
    # the board can be drawn without waiting for the next change.
    class FetchTableView < Shared::BaseInteraction
      def initialize(
        table_repo: Persistence::Postgres::TableRepository.new,
        state_store: Persistence::Redis::GameStateStore.new,
        card_catalog: Persistence::Postgres::CardCatalogRepository.new
      )
        @table_repo = table_repo
        @state_store = state_store
        @card_catalog = card_catalog
      end

      def call(table_slug:, seat_id:)
        table = @table_repo.find_by_slug(table_slug)
        return Failure[:not_found, "Table not found"] unless table

        views = Views::ViewPublisher.new(card_catalog: @card_catalog).views_for(
          state: @state_store.fetch(table_slug: table_slug), seats: @table_repo.seats_for(table), viewer_seat_ids: [ seat_id.to_s ]
        )
        Success(views.fetch(seat_id.to_s))
      end
    end
  end
end
