require "test_helper"

class TableChannelTest < ActionCable::Channel::TestCase
  setup do
    @table = GameTable.create!(format: "commander", host_session_id: "host-session", max_seats: 4)
    @seat = @table.seats.create!(seat_number: 1, session_id: "guest-1", display_name: "Alice")
    @other_seat = @table.seats.create!(seat_number: 2, session_id: "guest-2", display_name: "Bob")
    @state_store = Persistence::Redis::GameStateStore.new

    seat_state = Table::Entities::SeatState.new(
      zones: { "hand" => [ "ci_hand" ], "battlefield" => [ "ci_1" ] },
      instances: { "ci_1" => Table::Entities::CardInstance.new(card_id: 1), "ci_hand" => Table::Entities::CardInstance.new(card_id: 2) }
    )
    @state_store.save(table_slug: @table.slug, state: Table::Entities::GameState.blank.with_seat(@seat.id.to_s, seat_state))
  end

  teardown { @state_store.delete(table_slug: @table.slug) }

  def seat_stream(seat) = Broadcasting::ActionCableBroadcaster.seat_stream_name(@table.slug, seat.id.to_s)

  test "rejects a subscription without the seat's token" do
    stub_connection(guest_id: "guest-1")
    subscribe(table_slug: @table.slug, seat_id: @seat.id)

    assert subscription.rejected?
  end

  test "rejects another seat's token" do
    stub_connection(guest_id: "guest-1")
    subscribe(table_slug: @table.slug, seat_id: @seat.id, seat_token: @other_seat.token)

    assert subscription.rejected?
  end

  test "the seat token alone is enough, whatever guest the connection is" do
    stub_connection(guest_id: "a-browser-that-lost-its-cookies")
    subscribe(table_slug: @table.slug, seat_id: @seat.id, seat_token: @seat.token)

    assert subscription.confirmed?
  end

  test "streams the seat's private channel and sends the current table on subscribe" do
    stub_connection(guest_id: "guest-1")
    subscribe(table_slug: @table.slug, seat_id: @seat.id, seat_token: @seat.token)

    assert subscription.confirmed?
    assert_has_stream seat_stream(@seat)
    view = transmissions.last
    assert_equal "table_view", view["type"]
    assert_equal [ "ci_hand" ], view["seats"].first["zones"]["hand"].map { |c| c["id"] }
  end

  test "a command pushes each seat its own view" do
    stub_connection(guest_id: "guest-1")
    subscribe(table_slug: @table.slug, seat_id: @seat.id, seat_token: @seat.token)

    perform :move_card, card_instance_id: "ci_1", to_zone: "hand"

    mine = ActiveSupport::JSON.decode(broadcasts(seat_stream(@seat)).last)
    theirs = ActiveSupport::JSON.decode(broadcasts(seat_stream(@other_seat)).last)
    assert_equal %w[ci_hand ci_1], mine["seats"].first["zones"]["hand"].map { |c| c["id"] }
    assert_nil theirs["seats"].first["zones"]["hand"]
    assert_equal 2, theirs["seats"].first["zone_counts"]["hand"]
  end

  test "a failed command transmits the error back to the caller only" do
    stub_connection(guest_id: "guest-1")
    subscribe(table_slug: @table.slug, seat_id: @seat.id, seat_token: @seat.token)

    perform :move_card, card_instance_id: "does_not_exist", to_zone: "hand"

    assert_equal({ "type" => "error", "error" => "not_found", "message" => "Card instance not found" }, transmissions.last)
    assert_empty broadcasts(seat_stream(@other_seat))
  end

  test "deck tokens come back to the asking player as a list" do
    stub_connection(guest_id: "guest-1")
    subscribe(table_slug: @table.slug, seat_id: @seat.id, seat_token: @seat.token)

    perform :deck_tokens

    assert_equal({ "type" => "deck_tokens", "tokens" => [] }, transmissions.last)
  end
end
