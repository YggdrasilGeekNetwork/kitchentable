require "test_helper"

class TableViewTest < ActiveSupport::TestCase
  Seat = Struct.new(:id, :display_name, :seat_number)

  def instance(card_id, **attrs) = Table::Entities::CardInstance.new(card_id: card_id, **attrs)

  setup do
    @seats = [ Seat.new(1, "Alice", 1), Seat.new(2, "Bob", 2), Seat.new(3, "Carol", 3) ]
    alice = Table::Entities::SeatState.new(
      zones: { "hand" => %w[a_hand], "library" => %w[a_lib1 a_lib2], "battlefield" => %w[a_bf a_morph], "graveyard" => %w[a_gy] },
      instances: { "a_hand" => instance(1), "a_lib1" => instance(2), "a_lib2" => instance(3), "a_bf" => instance(4, tapped: true),
                   "a_morph" => instance(5, face_down: true), "a_gy" => instance(6) }
    )
    bob = Table::Entities::SeatState.new(
      zones: { "hand" => %w[b_hand1 b_hand2], "library" => %w[b_lib1 b_lib2 b_lib3] },
      instances: { "b_hand1" => instance(11), "b_hand2" => instance(12), "b_lib1" => instance(13), "b_lib2" => instance(14), "b_lib3" => instance(15) }
    )
    @state = Table::Entities::GameState.new(active_seat_id: "1").with_seat("1", alice).with_seat("2", bob)
  end

  def view_for(viewer, state = @state)
    view = Table::Views::TableView.new(state: state, seats: @seats, viewer_seat_id: viewer)
    [ view.to_h, view.card_ids ]
  end

  def seat(view, id) = view["seats"].find { |s| s["seat_id"] == id }

  test "a player sees their own hand; others only its size" do
    alice_view, alice_ids = view_for("1")
    bob_view, bob_ids = view_for("2")

    assert_equal [ 1 ], seat(alice_view, "1")["zones"]["hand"].map { |c| c["card_id"] }
    assert_nil seat(bob_view, "1")["zones"]["hand"]
    assert_equal 1, seat(bob_view, "1")["zone_counts"]["hand"]
    assert_includes alice_ids, 1
    refute_includes bob_ids, 1
  end

  test "libraries are never listed, not even to their owner" do
    alice_view, alice_ids = view_for("1")

    assert_nil seat(alice_view, "1")["zones"]["library"]
    assert_nil seat(alice_view, "1")["library_top"]
    assert_equal 2, seat(alice_view, "1")["zone_counts"]["library"]
    refute_includes alice_ids, 2
  end

  test "public zones are visible to everyone, with tapped state and controller" do
    bob_view, = view_for("2")
    battlefield = seat(bob_view, "1")["zones"]["battlefield"]

    assert_equal 4, battlefield.first["card_id"]
    assert battlefield.first["tapped"]
    assert_equal "1", battlefield.first["controller_seat_id"]
    assert_equal [ 6 ], seat(bob_view, "1")["zones"]["graveyard"].map { |c| c["card_id"] }
  end

  test "a face-down card's identity is hidden from everyone but its controller" do
    alice_view, alice_ids = view_for("1")
    bob_view, bob_ids = view_for("2")

    assert_equal 5, seat(alice_view, "1")["zones"]["battlefield"].last["card_id"]
    assert_nil seat(bob_view, "1")["zones"]["battlefield"].last["card_id"]
    assert seat(bob_view, "1")["zones"]["battlefield"].last["face_down"]
    assert_includes alice_ids, 5
    refute_includes bob_ids, 5
  end

  test "peeking shows the viewer only the cards they revealed from that library" do
    peeking = @state.with_seat("1", @state.seat("1").with(peek: { "seat_id" => "2", "card_instance_ids" => %w[b_lib1 b_lib2] }))

    alice_view, alice_ids = view_for("1", peeking)
    carol_view, carol_ids = view_for("3", peeking)
    bob_view, = view_for("2", peeking)

    assert_equal [ 13, 14 ], seat(alice_view, "2")["library_top"].map { |c| c["card_id"] }
    assert_includes alice_ids, 13
    assert_nil seat(carol_view, "2")["library_top"]
    refute_includes carol_ids, 13
    assert_nil seat(bob_view, "2")["library_top"], "the library's owner doesn't get to see it too"
    assert_equal "2", seat(bob_view, "1")["peek"]["seat_id"], "everyone knows who is looking"
  end

  test "a library played with its top card revealed shows that card to everyone" do
    revealed_top = @state.with_seat("2", @state.seat("2").with(top_revealed: true))

    carol_view, carol_ids = view_for("3", revealed_top)

    assert_equal 13, seat(carol_view, "2")["library_top_card"]["card_id"]
    assert_includes carol_ids, 13
    assert_nil seat(carol_view, "1")["library_top_card"]
  end

  test "revealed cards are visible to everyone while they stay revealed" do
    revealed = @state.with(reveals: [ { "id" => "r1", "by_seat_id" => "2", "owner_seat_id" => "2", "card_instance_ids" => %w[b_hand1] } ])

    carol_view, carol_ids = view_for("3", revealed)

    assert_equal [ 11 ], carol_view["reveals"].first["cards"].map { |c| c["card_id"] }
    assert_includes carol_ids, 11
    refute_includes carol_ids, 12
  end

  test "a reveal whose cards are all gone disappears" do
    revealed = @state.with(reveals: [ { "id" => "r1", "by_seat_id" => "2", "owner_seat_id" => "2", "card_instance_ids" => %w[gone] } ])

    assert_empty view_for("3", revealed).first["reveals"]
  end

  test "seats not dealt in yet appear as not ready" do
    carol = seat(view_for("1").first, "3")

    assert_equal({ "seat_id" => "3", "display_name" => "Carol", "seat_number" => 3, "ready" => false }, carol)
  end

  test "carries whose turn it is and the viewer's own seat id" do
    view, = view_for("2")

    assert_equal "1", view["active_seat_id"]
    assert_equal "2", view["viewer_seat_id"]
  end
end
