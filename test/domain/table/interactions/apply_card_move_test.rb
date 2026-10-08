require "test_helper"

class ApplyCardMoveTest < ActiveSupport::TestCase
  include GameTestHelper

  Move = Table::Interactions::ApplyCardMove

  setup do
    build_game(seats: {
      "1" => seat_state(hand: { "h1" => card(10, owner: "1"), "h2" => card(11, owner: "1") },
                        library: { "l1" => card(12, owner: "1"), "l2" => card(13, owner: "1") },
                        battlefield: { "b1" => card(14, owner: "1", tapped: true, counters: { "+1/+1" => 2 }, x: 10, y: 20) }),
      "2" => seat_state(hand: { "opp_h" => card(20, owner: "2") },
                        library: { "opp_l1" => card(21, owner: "2"), "opp_l2" => card(22, owner: "2") },
                        battlefield: { "opp_b" => card(23, owner: "2") },
                        graveyard: { "opp_g" => card(24, owner: "2") })
    })
  end

  test "plays a card from hand onto the battlefield at a position" do
    result = play(Move, seat_id: "1", card_instance_id: "h1", to_zone: "battlefield", x: 30.5, y: 40)

    assert result.success?, result.inspect
    assert_equal %w[b1 h1], zone("1", "battlefield")
    assert_equal [ 30.5, 40.0 ], [ state.seat("1").instances["h1"].x, state.seat("1").instances["h1"].y ]
    assert_equal 10, last_log.payload["card_id"]
  end

  test "repositioning on the battlefield isn't logged" do
    play(Move, seat_id: "1", card_instance_id: "b1", to_zone: "battlefield", x: 50, y: 50)

    assert_equal 50.0, state.seat("1").instances["b1"].x
    assert_nil last_log
  end

  test "leaving the battlefield resets tapped state, counters and position" do
    play(Move, seat_id: "1", card_instance_id: "b1", to_zone: "graveyard")

    moved = state.seat("1").instances["b1"]
    refute moved.tapped
    assert_empty moved.counters
    assert_nil moved.x
  end

  test "puts a card on the bottom of the library with a negative position" do
    play(Move, seat_id: "1", card_instance_id: "h1", to_zone: "library", to_position: -1)

    assert_equal %w[l1 l2 h1], zone("1", "library")
    assert_nil last_log.payload["card_id"], "hand to library stays hidden"
    assert last_log.payload["to_bottom"]
  end

  test "puts a card on top of the library with position 0" do
    play(Move, seat_id: "1", card_instance_id: "h1", to_zone: "library", to_position: 0)

    assert_equal %w[h1 l1 l2], zone("1", "library")
  end

  test "takes control of an opponent's permanent" do
    result = play(Move, seat_id: "1", card_instance_id: "opp_b", to_zone: "battlefield", to_seat_id: "1", x: 5, y: 5)

    assert result.success?, result.inspect
    assert_includes zone("1", "battlefield"), "opp_b"
    assert_empty zone("2", "battlefield")
    assert_equal "2", state.seat("1").instances["opp_b"].owner_seat_id
  end

  test "gives a permanent to another player" do
    play(Move, seat_id: "1", card_instance_id: "b1", to_zone: "battlefield", to_seat_id: "2")

    assert_includes zone("2", "battlefield"), "b1"
  end

  test "a stolen permanent leaving the battlefield goes to its owner's zone" do
    play(Move, seat_id: "1", card_instance_id: "opp_b", to_zone: "battlefield", to_seat_id: "1")
    play(Move, seat_id: "1", card_instance_id: "opp_b", to_zone: "graveyard")

    assert_includes zone("2", "graveyard"), "opp_b"
    refute_includes zone("1", "graveyard"), "opp_b"
  end

  test "reanimates from an opponent's graveyard (a public zone)" do
    result = play(Move, seat_id: "1", card_instance_id: "opp_g", to_zone: "battlefield")

    assert result.success?, result.inspect
    assert_includes zone("1", "battlefield"), "opp_g"
  end

  test "can't take a card from an opponent's hand or library" do
    hand = play(Move, seat_id: "1", card_instance_id: "opp_h", to_zone: "battlefield")
    library = play(Move, seat_id: "1", card_instance_id: "opp_l1", to_zone: "exile")

    assert_equal :forbidden, hand.failure.first
    assert_equal :forbidden, library.failure.first
    assert_equal %w[opp_h], zone("2", "hand")
  end

  test "can move an opponent's library card while peeking at it, but not deeper ones" do
    state_store.save(table_slug: "table-1", state: state.with_seat("1", state.seat("1").with(peek: { "seat_id" => "2", "card_instance_ids" => %w[opp_l1] })))

    deeper = play(Move, seat_id: "1", card_instance_id: "opp_l2", to_zone: "exile")
    top = play(Move, seat_id: "1", card_instance_id: "opp_l1", to_zone: "exile")

    assert_equal :forbidden, deeper.failure.first
    assert top.success?, top.inspect
    assert_equal %w[opp_l1], zone("2", "exile"), "exiled to its owner's exile"
  end

  test "can move a card from an opponent's hand while it's revealed" do
    state_store.save(table_slug: "table-1", state: state.with(reveals: [
      { "id" => "r", "by_seat_id" => "2", "owner_seat_id" => "2", "card_instance_ids" => %w[opp_h] }
    ]))

    result = play(Move, seat_id: "1", card_instance_id: "opp_h", to_zone: "graveyard")

    assert result.success?, result.inspect
    assert_equal %w[opp_h opp_g], zone("2", "graveyard"), "lands on top of the pile"
  end

  test "a token leaving the battlefield ceases to exist" do
    state_store.save(table_slug: "table-1", state: state.with_seat("1", state.seat("1").with_card("tok", card(99, owner: "1", token: true), zone: "battlefield")))

    play(Move, seat_id: "1", card_instance_id: "tok", to_zone: "graveyard")

    assert_nil state.locate("tok")
  end

  test "rejects unknown zones and cards" do
    assert_equal :validation_error, play(Move, seat_id: "1", card_instance_id: "h1", to_zone: "sideboard").failure.first
    assert_equal :not_found, play(Move, seat_id: "1", card_instance_id: "nope", to_zone: "hand").failure.first
  end

  test "pushes every seat its own redacted view" do
    play(Move, seat_id: "1", card_instance_id: "h1", to_zone: "battlefield")

    assert_equal %w[1 2], broadcaster.seat_broadcasts.map(&:seat_id)
    mine = broadcaster.view_for("1")["seats"].find { |s| s["seat_id"] == "1" }
    theirs = broadcaster.view_for("2")["seats"].find { |s| s["seat_id"] == "1" }
    assert_equal %w[h2], mine["zones"]["hand"].map { |c| c["id"] }
    assert_nil theirs["zones"]["hand"]
    assert_equal 1, theirs["zone_counts"]["hand"]
  end

  test "a failed move changes nothing and broadcasts nothing" do
    play(Move, seat_id: "1", card_instance_id: "opp_h", to_zone: "battlefield")

    assert_empty broadcaster.seat_broadcasts
    assert_equal %w[opp_h], zone("2", "hand")
  end
end
