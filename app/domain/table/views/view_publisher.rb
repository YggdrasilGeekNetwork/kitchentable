module Table
  module Views
    # Builds every seat's TableView for a state, resolving all visible card ids to
    # catalog data in one lookup, and either returns them or pushes each one to its
    # seat's private stream.
    class ViewPublisher
      def initialize(card_catalog:, broadcaster: nil)
        @card_catalog = card_catalog
        @broadcaster = broadcaster
      end

      def views_for(state:, seats:, viewer_seat_ids: seats.map { |s| s.id.to_s })
        views = viewer_seat_ids.index_with { |viewer| TableView.new(state: state, seats: seats, viewer_seat_id: viewer) }
        views.each_value(&:to_h)

        catalog = @card_catalog.find_many(views.values.flat_map { |v| v.card_ids.to_a }.uniq)
        views.transform_values do |view|
          view.to_h.merge("cards" => view.card_ids.filter_map { |id| catalog[id] }.to_h { |card| [ card.id.to_s, CardView.call(card) ] })
        end
      end

      def publish(table_slug:, state:, seats:)
        views_for(state: state, seats: seats).each do |seat_id, view|
          @broadcaster.broadcast_to_seat(table_slug: table_slug, seat_id: seat_id, payload: view)
        end
      end
    end
  end
end
