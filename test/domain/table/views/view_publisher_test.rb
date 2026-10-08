require "test_helper"

class ViewPublisherTest < ActiveSupport::TestCase
  Seat = Struct.new(:id, :display_name, :seat_number)

  setup do
    @catalog = Fakes::FakeCardCatalog.new
    @bolt = @catalog.register(name: "Lightning Bolt", type_line: "Instant", image_uris: { "normal" => "https://img/bolt.jpg" })
    @norn = @catalog.register(name: "Elesh Norn // The Argent Etchings", card_faces: [
      { "name" => "Elesh Norn", "image_uris" => { "normal" => "https://img/front.jpg" } },
      { "name" => "The Argent Etchings", "image_uris" => { "normal" => "https://img/back.jpg" } }
    ])
    seat_state = Table::Entities::SeatState.new(
      zones: { "hand" => %w[h], "battlefield" => %w[b] },
      instances: { "h" => Table::Entities::CardInstance.new(card_id: @bolt.id), "b" => Table::Entities::CardInstance.new(card_id: @norn.id) }
    )
    @state = Table::Entities::GameState.new.with_seat("1", seat_state)
    @seats = [ Seat.new(1, "Alice", 1), Seat.new(2, "Bob", 2) ]
  end

  test "each view carries catalog data only for the cards its viewer can see" do
    views = Table::Views::ViewPublisher.new(card_catalog: @catalog).views_for(state: @state, seats: @seats)

    assert_equal [ @bolt.id.to_s, @norn.id.to_s ].sort, views["1"]["cards"].keys.sort
    assert_equal [ @norn.id.to_s ], views["2"]["cards"].keys
  end

  test "double-faced cards carry an image per face, others a single image" do
    cards = Table::Views::ViewPublisher.new(card_catalog: @catalog).views_for(state: @state, seats: @seats)["1"]["cards"]

    assert_equal %w[https://img/front.jpg https://img/back.jpg], cards[@norn.id.to_s]["faces"].map { |f| f["image"] }
    assert_equal [ "Elesh Norn", "The Argent Etchings" ], cards[@norn.id.to_s]["faces"].map { |f| f["name"] }
    assert_equal %w[https://img/bolt.jpg], cards[@bolt.id.to_s]["faces"].map { |f| f["image"] }
  end

  test "publishing pushes every seat its own view on its private stream" do
    broadcaster = Fakes::FakeBroadcaster.new

    Table::Views::ViewPublisher.new(card_catalog: @catalog, broadcaster: broadcaster)
      .publish(table_slug: "t", state: @state, seats: @seats)

    assert_equal %w[1 2], broadcaster.seat_broadcasts.map(&:seat_id)
    assert_equal "2", broadcaster.view_for("2")["viewer_seat_id"]
  end
end
