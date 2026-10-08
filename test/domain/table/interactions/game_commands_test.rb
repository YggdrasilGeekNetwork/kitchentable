require "test_helper"

# One test class per command, sharing a two-seat table.
module GameCommandsTest
  class Base < ActiveSupport::TestCase
    include GameTestHelper

    I = Table::Interactions

    setup do
      build_game(seats: {
        "1" => seat_state(
          hand: { "h1" => card(10, owner: "1") },
          library: (1..5).to_h { |i| [ "l#{i}", card(100 + i, owner: "1") ] },
          battlefield: { "b1" => card(14, owner: "1", tapped: true), "b2" => card(15, owner: "1", tapped: true) }
        ),
        "2" => seat_state(life_total: 40, hand: { "opp_h" => card(20, owner: "2") },
                          library: { "opp_l1" => card(21, owner: "2") },
                          battlefield: { "opp_b" => card(23, owner: "2") })
      }, active_seat_id: "1")
    end
  end

  class DrawTest < Base
    test "draws from the top of the library" do
      play(I::ApplyDraw, seat_id: "1", count: 2)

      assert_equal %w[h1 l1 l2], zone("1", "hand")
      assert_equal %w[l3 l4 l5], zone("1", "library")
      assert_equal 2, last_log.payload["count"]
    end

    test "draws only what's left when the library runs out" do
      play(I::ApplyDraw, seat_id: "1", count: 9)

      assert_empty zone("1", "library")
      assert_equal 5, last_log.payload["count"]
    end

    test "rejects silly counts" do
      assert_equal :validation_error, play(I::ApplyDraw, seat_id: "1", count: 0).failure.first
    end
  end

  class MillTest < Base
    test "puts the top cards into the graveyard, last milled on top" do
      play(I::ApplyMill, seat_id: "1", count: 2)

      assert_equal %w[l2 l1], zone("1", "graveyard")
      assert_equal %w[l3 l4 l5], zone("1", "library")
    end
  end

  class ShuffleTest < Base
    test "keeps the same cards in the library" do
      play(I::ApplyShuffle, seat_id: "1")

      assert_equal %w[l1 l2 l3 l4 l5], zone("1", "library").sort
      assert_equal "shuffle", last_log.event_type
    end
  end

  class TapTest < Base
    test "taps any battlefield permanent, including an opponent's" do
      play(I::ApplyTapCard, seat_id: "1", card_instance_id: "opp_b", tapped: true)

      assert state.seat("2").instances["opp_b"].tapped
    end

    test "only battlefield cards can be tapped" do
      assert_equal :validation_error, play(I::ApplyTapCard, seat_id: "1", card_instance_id: "h1", tapped: true).failure.first
    end

    test "untap all untaps only the player's own permanents" do
      play(I::ApplyTapCard, seat_id: "2", card_instance_id: "opp_b", tapped: true)
      play(I::ApplyTapAll, seat_id: "1", tapped: false)

      refute state.seat("1").instances["b1"].tapped
      refute state.seat("1").instances["b2"].tapped
      assert state.seat("2").instances["opp_b"].tapped
    end
  end

  class LifeTest < Base
    test "changes the player's own life by default" do
      play(I::ApplyLifeChange, seat_id: "1", delta: -3)

      assert_equal 17, state.seat("1").life_total
    end

    test "changes another player's life" do
      play(I::ApplyLifeChange, seat_id: "1", delta: -5, target_seat_id: "2")

      assert_equal 35, state.seat("2").life_total
      assert_equal({ "target_seat_id" => "2", "delta" => -5, "life_total" => 35 }, last_log.payload)
    end
  end

  class CountersTest < Base
    test "player counters add up, stay at zero (never below) and go away only when removed" do
      play(I::ApplyPlayerCounter, seat_id: "1", key: "poison", delta: 3, target_seat_id: "2")
      assert_equal({ "poison" => 3 }, state.seat("2").counters)

      play(I::ApplyPlayerCounter, seat_id: "1", key: "poison", delta: -5, target_seat_id: "2")
      assert_equal({ "poison" => 0 }, state.seat("2").counters)

      play(I::ApplyPlayerCounter, seat_id: "1", key: "poison", remove: true, target_seat_id: "2")
      assert_empty state.seat("2").counters
    end

    test "card counters go on public cards only" do
      play(I::ApplyCardCounter, seat_id: "1", card_instance_id: "b1", key: "+1/+1", delta: 2)

      assert_equal({ "+1/+1" => 2 }, state.seat("1").instances["b1"].counters)
      assert_equal :validation_error, play(I::ApplyCardCounter, seat_id: "1", card_instance_id: "h1", key: "x", delta: 1).failure.first
    end

    test "counter names can't be blank" do
      assert_equal :validation_error, play(I::ApplyPlayerCounter, seat_id: "1", key: " ", delta: 1).failure.first
    end
  end

  class FlipAndFaceDownTest < Base
    test "flips a battlefield card to its other face and back" do
      play(I::ApplyFlipCard, seat_id: "1", card_instance_id: "b1")
      assert_equal 1, state.seat("1").instances["b1"].face_index

      play(I::ApplyFlipCard, seat_id: "1", card_instance_id: "b1")
      assert_equal 0, state.seat("1").instances["b1"].face_index
    end

    test "a face-down card hides from opponents and its log entry doesn't name it" do
      play(I::ApplyFaceDown, seat_id: "1", card_instance_id: "b1", face_down: true)

      assert_nil last_log.payload["card_id"]
      opponent_view = broadcaster.view_for("2")["seats"].find { |s| s["seat_id"] == "1" }
      assert_nil opponent_view["zones"]["battlefield"].find { |c| c["id"] == "b1" }["card_id"]
    end
  end

  class RevealTest < Base
    test "reveals cards from the player's hand to everyone" do
      result = play(I::ApplyReveal, seat_id: "2", card_instance_ids: %w[opp_h])

      assert result.success?, result.inspect
      reveal = broadcaster.view_for("1")["reveals"].first
      assert_equal [ 20 ], reveal["cards"].map { |c| c["card_id"] }
    end

    test "can't reveal someone else's hidden cards" do
      assert_equal :forbidden, play(I::ApplyReveal, seat_id: "1", card_instance_ids: %w[opp_h]).failure.first
    end

    test "only the revealer can end a reveal" do
      play(I::ApplyReveal, seat_id: "2", card_instance_ids: %w[opp_h])
      reveal_id = state.reveals.first["id"]

      assert_equal :forbidden, play(I::ApplyEndReveal, seat_id: "1", reveal_id: reveal_id).failure.first
      play(I::ApplyEndReveal, seat_id: "2", reveal_id: reveal_id)
      assert_empty state.reveals
    end
  end

  class PeekTest < Base
    test "looks at the top of another player's library, and everyone is told" do
      play(I::ApplyPeek, seat_id: "1", count: 3, target_seat_id: "2")

      assert_equal({ "seat_id" => "2", "card_instance_ids" => %w[opp_l1], "search" => false }, state.seat("1").peek)
      assert_equal({ "target_seat_id" => "2", "count" => 3 }, last_log.payload)
      top = broadcaster.view_for("1")["seats"].find { |s| s["seat_id"] == "2" }["library_top"]
      assert_equal [ 21 ], top.map { |c| c["card_id"] }
    end

    test "defaults to the player's own library, and stops" do
      play(I::ApplyPeek, seat_id: "1", count: 2)
      assert_equal "1", state.seat("1").peek["seat_id"]

      play(I::ApplyStopPeek, seat_id: "1")
      assert_nil state.seat("1").peek
    end
  end

  class RevealedFromLibraryTest < Base
    def peek(count) = play(I::ApplyPeek, seat_id: "1", count: count)
    def revealed = state.seat("1").peek&.dig("card_instance_ids")
    def shown = broadcaster.view_for("1")["seats"].find { |s| s["seat_id"] == "1" }["library_top"]&.map { |c| c["id"] }

    test "is a fixed set: a moved card leaves it and no other card slides in" do
      peek(3)
      play(I::ApplyCardMove, seat_id: "1", card_instance_id: "l1", to_zone: "hand")

      assert_equal %w[l2 l3], revealed
      assert_equal %w[l2 l3], shown
      assert_equal :forbidden, play(I::ApplyCardMove, seat_id: "2", card_instance_id: "l4", to_zone: "hand").failure.first
    end

    test "putting a revealed card back on top also takes it out of the reveal" do
      peek(2)
      play(I::ApplyCardMove, seat_id: "1", card_instance_id: "l2", to_zone: "library", to_position: 0)

      assert_equal %w[l1], revealed
      assert_equal "l2", zone("1", "library").first
    end

    test "ends once every revealed card was moved" do
      peek(1)
      play(I::ApplyCardMove, seat_id: "1", card_instance_id: "l1", to_zone: "graveyard")

      assert_nil state.seat("1").peek
    end

    test "shuffling that library ends it" do
      peek(2)
      play(I::ApplyShuffle, seat_id: "1")

      assert_nil state.seat("1").peek
    end

    test "the rest go to the bottom (or top) in a random order, and the reveal ends" do
      peek(3)
      play(I::ApplyCardMove, seat_id: "1", card_instance_id: "l2", to_zone: "hand")
      play(I::ApplyPeekRemaining, seat_id: "1", placement: "bottom")

      assert_equal %w[l4 l5], zone("1", "library").first(2)
      assert_equal %w[l1 l3], zone("1", "library").last(2).sort
      assert_nil state.seat("1").peek
      assert_equal({ "target_seat_id" => "1", "count" => 2, "placement" => "bottom" }, last_log.payload)
    end

    test "the rest can go back on top too" do
      peek(2)
      play(I::ApplyPeekRemaining, seat_id: "1", placement: "top")

      assert_equal %w[l1 l2], zone("1", "library").first(2).sort
    end

    test "playing with the top card revealed is a toggle" do
      play(I::ApplyTopRevealed, seat_id: "1", revealed: true)
      top = broadcaster.view_for("2")["seats"].find { |s| s["seat_id"] == "1" }["library_top_card"]
      assert_equal 101, top["card_id"]

      play(I::ApplyTopRevealed, seat_id: "1", revealed: false)
      assert_nil broadcaster.view_for("2")["seats"].find { |s| s["seat_id"] == "1" }["library_top_card"]
    end
  end

  class LibrarySearchTest < Base
    test "shows the player their whole library, and tells everyone they're searching" do
      play(I::ApplyPeek, seat_id: "1", search: true)

      top = broadcaster.view_for("1")["seats"].find { |s| s["seat_id"] == "1" }["library_top"]
      assert_equal (101..105).to_a, top.map { |c| c["card_id"] }
      assert_equal [ "library_search", {} ], [ last_log.event_type, last_log.payload ]
      assert_nil broadcaster.view_for("2")["seats"].find { |s| s["seat_id"] == "1" }["library_top"]
    end

    test "any card found can be taken, however deep" do
      play(I::ApplyPeek, seat_id: "1", search: true)

      assert play(I::ApplyCardMove, seat_id: "1", card_instance_id: "l5", to_zone: "hand").success?
      assert_includes zone("1", "hand"), "l5"
    end

    test "only your own library can be searched" do
      assert_equal :forbidden, play(I::ApplyPeek, seat_id: "1", search: true, target_seat_id: "2").failure.first
    end
  end

  class BatchMoveTest < Base
    def moves(*ids, **extra) = ids.map { |id| { "card_instance_id" => id, **extra } }

    test "moves several cards in one update" do
      result = play(I::ApplyCardMoves, seat_id: "1", moves: moves("b1", "b2", "h1"), to_zone: "graveyard")

      assert result.success?, result.inspect
      assert_equal %w[b1 b2 h1].sort, zone("1", "graveyard").sort
      assert_equal 2, broadcaster.seat_broadcasts.size, "one view per seat, not one per card"
    end

    test "cards sent to the bottom keep the selection order; to the top, the first ends on top" do
      play(I::ApplyCardMoves, seat_id: "1", moves: moves("b1", "b2"), to_zone: "library", to_position: -1)
      assert_equal %w[b1 b2], zone("1", "library").last(2)

      play(I::ApplyCardMoves, seat_id: "1", moves: moves("l1", "l2"), to_zone: "graveyard")
      play(I::ApplyCardMoves, seat_id: "1", moves: moves("l1", "l2"), to_zone: "library", to_position: 0)
      assert_equal %w[l1 l2], zone("1", "library").first(2)
    end

    test "places each card where the client put it on the battlefield" do
      play(I::ApplyCardMoves, seat_id: "1", to_zone: "battlefield",
           moves: [ { "card_instance_id" => "h1", "x" => 10, "y" => 70 }, { "card_instance_id" => "l1", "x" => 22, "y" => 70 } ])

      assert_equal [ 10.0, 22.0 ], %w[h1 l1].map { |id| state.seat("1").instances[id].x }
    end

    test "is all or nothing" do
      result = play(I::ApplyCardMoves, seat_id: "1", moves: moves("b1", "opp_h"), to_zone: "exile")

      assert_equal :forbidden, result.failure.first
      assert_includes zone("1", "battlefield"), "b1"
      assert_empty broadcaster.seat_broadcasts
    end
  end

  class ManaPoolTest < Base
    def mana(**args) = play(I::ApplyManaPool, seat_id: "1", **args)

    test "tracks mana by color, never below zero, and empties on clear" do
      mana(color: "G", delta: 3)
      mana(color: "U", delta: 1)
      mana(color: "G", delta: -1)
      mana(color: "U", delta: -5)
      assert_equal({ "G" => 2 }, state.seat("1").mana_pool)
      assert_equal({ "G" => 2 }, broadcaster.view_for("1")["seats"].find { |s| s["seat_id"] == "1" }["mana_pool"])

      mana(clear: true)
      assert_empty state.seat("1").mana_pool
    end

    test "rejects unknown colors" do
      assert_equal :validation_error, mana(color: "X", delta: 1).failure.first
    end
  end

  class CreateCardTest < Base
    def created = zone("1", "battlefield").drop(2).map { |id| state.seat("1").instances[id] }

    test "creates tokens on the player's battlefield by name" do
      soldier = catalog.register(name: "Soldier", type_line: "Token Creature — Soldier")

      result = play(I::ApplyCreateCard, seat_id: "1", name: "soldier", count: 2, x: 10, y: 10)

      assert result.success?, result.inspect
      assert_equal [ soldier.id ] * 2, created.map(&:card_id)
      assert created.all?(&:token)
    end

    test "creates a token copy of a card by id" do
      result = play(I::ApplyCreateCard, seat_id: "1", card_id: catalog.register(name: "Deepglow Skate").id)

      assert result.success?, result.inspect
      assert created.first.token
    end

    test "adds a real (non-token) card from search" do
      play(I::ApplyCreateCard, seat_id: "1", card_id: catalog.register(name: "Sol Ring").id, token: false)

      refute created.first.token
    end

    test "creates a custom card with no catalog entry" do
      play(I::ApplyCreateCard, seat_id: "1", custom: { "name" => "Lorwyn Elemental", "type_line" => "Creature", "power" => "4", "toughness" => "4" })

      assert_nil created.first.card_id
      assert_equal "Lorwyn Elemental", created.first.custom["name"]
      assert_equal "Lorwyn Elemental", last_log.payload["custom_name"]
    end

    test "rejects unknown names and nameless custom cards" do
      assert_equal :validation_error, play(I::ApplyCreateCard, seat_id: "1", name: "Nope").failure.first
      assert_equal :validation_error, play(I::ApplyCreateCard, seat_id: "1", custom: { "name" => " " }).failure.first
    end
  end

  class TapAllTest < Base
    test "taps every permanent the player controls" do
      play(I::ApplyTapAll, seat_id: "1", tapped: false)
      play(I::ApplyTapAll, seat_id: "1", tapped: true)

      assert state.seat("1").instances.values_at("b1", "b2").all?(&:tapped)
      refute state.seat("2").instances["opp_b"].tapped
      assert_equal "tap_all", last_log.event_type
    end
  end

  class NewTurnTest < Base
    test "untaps everything and draws a card" do
      play(I::ApplyNewTurn, seat_id: "1")

      refute state.seat("1").instances.values_at("b1", "b2").any?(&:tapped)
      assert_equal %w[h1 l1], zone("1", "hand")
    end
  end

  class ProliferateTest < Base
    test "adds one of each counter kind on the player's permanents and the player" do
      play(I::ApplyCardCounter, seat_id: "1", card_instance_id: "b1", key: "+1/+1", delta: 2)
      play(I::ApplyCardCounter, seat_id: "1", card_instance_id: "b1", key: "Carga", delta: 1)
      play(I::ApplyPlayerCounter, seat_id: "1", key: "Energia", delta: 1)
      play(I::ApplyPlayerCounter, seat_id: "1", key: "Veneno", delta: 0)
      play(I::ApplyCardCounter, seat_id: "2", card_instance_id: "opp_b", key: "+1/+1", delta: 1)

      play(I::ApplyProliferate, seat_id: "1")

      assert_equal({ "+1/+1" => 3, "Carga" => 2 }, state.seat("1").instances["b1"].counters)
      assert_empty state.seat("1").instances["b2"].counters
      assert_equal({ "Energia" => 2, "Veneno" => 0 }, state.seat("1").counters, "counters at zero aren't proliferated")
      assert_equal({ "+1/+1" => 1 }, state.seat("2").instances["opp_b"].counters, "opponents' permanents untouched")
    end
  end

  class PtModifierTest < Base
    test "adjusts power and toughness, reset when the card leaves the battlefield" do
      play(I::ApplyPtModifier, seat_id: "1", card_instance_id: "b1", power: 3, toughness: 3)
      play(I::ApplyPtModifier, seat_id: "1", card_instance_id: "b1", power: -1)
      assert_equal [ 2, 3 ], [ state.seat("1").instances["b1"].power_mod, state.seat("1").instances["b1"].toughness_mod ]

      play(I::ApplyCardMove, seat_id: "1", card_instance_id: "b1", to_zone: "hand")
      assert_equal [ 0, 0 ], [ state.seat("1").instances["b1"].power_mod, state.seat("1").instances["b1"].toughness_mod ]
    end

    test "only on the battlefield" do
      assert_equal :validation_error, play(I::ApplyPtModifier, seat_id: "1", card_instance_id: "h1", power: 1).failure.first
    end
  end

  class RemoveCardTest < Base
    test "takes a card out of the game entirely" do
      play(I::ApplyRemoveCard, seat_id: "1", card_instance_id: "b1")

      assert_nil state.locate("b1")
      assert_equal "battlefield", last_log.payload["from_zone"]
    end

    test "can't remove a card from someone else's hand" do
      assert_equal :forbidden, play(I::ApplyRemoveCard, seat_id: "1", card_instance_id: "opp_h").failure.first
    end
  end

  class StackTest < Base
    test "casting puts the spell on the player's stack, visible to everyone, then it resolves" do
      play(I::ApplyCardMove, seat_id: "1", card_instance_id: "h1", to_zone: "stack")

      assert_equal %w[h1], zone("1", "stack")
      assert_equal 10, last_log.payload["card_id"], "a spell being cast is public"
      opponent_view = broadcaster.view_for("2")["seats"].find { |s| s["seat_id"] == "1" }
      assert_equal [ 10 ], opponent_view["zones"]["stack"].map { |c| c["card_id"] }

      play(I::ApplyCardMove, seat_id: "1", card_instance_id: "h1", to_zone: "graveyard")
      assert_empty zone("1", "stack")
      assert_equal "h1", zone("1", "graveyard").first
    end
  end

  class DiceTest < Base
    test "rolls on the server and logs the result" do
      rng = Struct.new(:value) { def rand(_range) = value }.new(4)

      result = call_interaction(I::ApplyDiceRoll,
                                deps: { table_repo: table_repo, state_store: state_store, broadcaster: broadcaster, card_catalog: catalog, rng: rng },
                                table_slug: "table-1", seat_id: "1", sides: 6)

      assert result.success?, result.inspect
      assert_equal({ "sides" => 6, "result" => 4 }, last_log.payload)
    end

    test "rejects one-sided dice" do
      assert_equal :validation_error, play(I::ApplyDiceRoll, seat_id: "1", sides: 1).failure.first
    end
  end

  class TurnTest < Base
    test "passes the turn to the next seat and wraps around" do
      play(I::ApplyPassTurn, seat_id: "1")
      assert_equal [ "2", 2 ], [ state.active_seat_id, state.turn_number ]

      play(I::ApplyPassTurn, seat_id: "2")
      assert_equal [ "1", 3 ], [ state.active_seat_id, state.turn_number ]
    end

    test "only the player whose turn it is can pass it" do
      assert_equal :forbidden, play(I::ApplyPassTurn, seat_id: "2").failure.first
      assert_equal "1", state.active_seat_id
    end

    test "a round goes by only when the turn comes back to the player who opened the game" do
      build_game(seats: { "1" => seat_state, "2" => seat_state, "3" => seat_state }, active_seat_id: "2")
      state_store.save(table_slug: "table-1", state: state.with(first_seat_id: "2"))

      play(I::ApplyPassTurn, seat_id: "2")
      assert_equal [ "3", 1 ], [ state.active_seat_id, state.round ]
      play(I::ApplyPassTurn, seat_id: "3")
      assert_equal [ "1", 1 ], [ state.active_seat_id, state.round ], "wrapping past the last seat isn't a new round"
      play(I::ApplyPassTurn, seat_id: "1")
      assert_equal [ "2", 2 ], [ state.active_seat_id, state.round ]
      assert last_log.payload["new_round"]
    end

    test "skips seats that haven't been dealt in" do
      build_game(seats: { "1" => seat_state, "2" => nil, "3" => seat_state }, active_seat_id: "1")

      play(I::ApplyPassTurn, seat_id: "1")

      assert_equal "3", state.active_seat_id
    end
  end

  class StartTurnTest < Base
    test "the active player starts their turn once: untap, draw" do
      play(I::ApplyStartTurn, seat_id: "1")

      assert_equal 1, state.seat("1").turns_taken
      assert_equal 1, last_log.payload["seat_turn"]
      assert state.turn_started
      refute state.seat("1").instances["b1"].tapped
      assert_equal %w[h1 l1], zone("1", "hand")
      assert_equal :validation_error, play(I::ApplyStartTurn, seat_id: "1").failure.first
    end

    test "passing the turn leaves the next player's turn not started" do
      play(I::ApplyStartTurn, seat_id: "1")
      play(I::ApplyPassTurn, seat_id: "1")

      assert_equal [ "2", false ], [ state.active_seat_id, state.turn_started ]
    end

    test "nobody else can start the very first turn" do
      assert_equal :forbidden, play(I::ApplyStartTurn, seat_id: "2", out_of_turn: true).failure.first
      assert_equal [ "1", false ], [ state.active_seat_id, state.turn_started ]
      assert broadcaster.seat_broadcasts.empty?
    end

    test "taking a turn out of order needs the confirmation, then makes you the active player" do
      play(I::ApplyStartTurn, seat_id: "1")
      assert_equal :forbidden, play(I::ApplyStartTurn, seat_id: "2").failure.first

      play(I::ApplyStartTurn, seat_id: "2", out_of_turn: true)

      assert_equal [ "2", true, 2 ], [ state.active_seat_id, state.turn_started, state.turn_number ]
      assert_equal [ 1, 1 ], [ state.seat("1").turns_taken, state.seat("2").turns_taken ], "each player counts their own turns"
      assert_equal %w[opp_h opp_l1], zone("2", "hand")
      assert last_log.payload["out_of_turn"]
    end
  end

  class ChatTest < Base
    test "logs the message" do
      play(I::ApplyChatMessage, seat_id: "2", message: "  gg  ")

      assert_equal [ "2", "chat", { "message" => "gg" } ], [ last_log.seat_id, last_log.event_type, last_log.payload ]
    end

    test "rejects empty messages" do
      assert_equal :validation_error, play(I::ApplyChatMessage, seat_id: "1", message: " ").failure.first
    end
  end

  class OpeningHandTest < Base
    setup do
      state_store.save(table_slug: "table-1", state: state.with_seat("1", state.seat("1").with(hand_kept: false)))
    end

    test "mulligan shuffles the hand back and draws a fresh 7, counting the mulligan" do
      play(I::ApplyMulligan, seat_id: "1")

      assert_equal 6, zone("1", "hand").size + 0, "only 6 cards exist in this small deck"
      assert_equal 1, state.seat("1").mulligan_count
    end

    test "keeping the hand ends mulligans" do
      play(I::ApplyKeepHand, seat_id: "1")

      assert state.seat("1").hand_kept
      assert_equal :validation_error, play(I::ApplyMulligan, seat_id: "1").failure.first
      assert_equal :validation_error, play(I::ApplyKeepHand, seat_id: "1").failure.first
    end
  end

  class CommanderDamageTest < Base
    setup do
      seat = state.seat("2").with_card("cmd", card(77, owner: "2", commander: true), zone: "command")
      state_store.save(table_slug: "table-1", state: state.with_seat("2", seat))
    end

    def damage(delta, target: "1") = play(I::ApplyCommanderDamage, seat_id: "1", commander_instance_id: "cmd", delta: delta, target_seat_id: target)

    test "is tracked per commander and comes off the life total" do
      damage(3)
      damage(2)

      assert_equal({ "cmd" => 5 }, state.seat("1").commander_damage)
      assert_equal 15, state.seat("1").life_total
      assert_equal({ "target_seat_id" => "1", "card_id" => 77, "delta" => 2, "total" => 5, "life_total" => 15, "lethal" => false },
                   last_log.payload)
    end

    test "lowering it gives the life back, but never below zero damage" do
      damage(3)
      damage(-5)

      assert_equal({ "cmd" => 0 }, state.seat("1").commander_damage)
      assert_equal 20, state.seat("1").life_total
    end

    test "flags lethal damage at 21" do
      damage(21)

      assert last_log.payload["lethal"]
    end

    test "still counts once the commander has been cast" do
      play(I::ApplyCardMove, seat_id: "2", card_instance_id: "cmd", to_zone: "battlefield")

      assert damage(4).success?
      assert_equal 16, state.seat("1").life_total
    end

    test "only commanders deal commander damage" do
      assert_equal :validation_error, play(I::ApplyCommanderDamage, seat_id: "1", commander_instance_id: "opp_b", delta: 1).failure.first
    end

    test "everyone sees every commander and every player's commander damage" do
      damage(6)

      view = broadcaster.view_for("2")
      assert_equal [ { "instance_id" => "cmd", "owner_seat_id" => "2", "card_id" => 77 } ], view["commanders"]
      assert_equal({ "cmd" => 6 }, view["seats"].find { |s| s["seat_id"] == "1" }["commander_damage"])
    end
  end

  class SummoningSicknessTest < ActiveSupport::TestCase
    include GameTestHelper

    I = Table::Interactions

    setup do
      @catalog = Fakes::FakeCardCatalog.new
      bear = @catalog.register(name: "Grizzly Bears", type_line: "Creature — Bear").id
      ring = @catalog.register(name: "Sol Ring", type_line: "Artifact").id
      dryad = @catalog.register(name: "Dryad Arbor", type_line: "Land Creature — Forest Dryad").id
      mdfc = @catalog.register(name: "Disciple of Freyalise // Garden of Freyalise", type_line: "Land // Creature — Elf Druid").id
      build_game(seats: {
        "1" => seat_state(hand: { "bear" => card(bear, owner: "1"), "ring" => card(ring, owner: "1"),
                                  "dryad" => card(dryad, owner: "1"), "mdfc" => card(mdfc, owner: "1") }),
        "2" => seat_state(battlefield: { "opp_bear" => card(bear, owner: "2") })
      }, active_seat_id: "1")
    end

    def enter(id) = play(I::ApplyCardMove, seat_id: "1", card_instance_id: id, to_zone: "battlefield")
    def sick?(seat_id, id) = state.seat(seat_id).instances[id].sick

    test "creatures entering the battlefield are summoning sick; other permanents aren't" do
      %w[bear ring dryad mdfc].each { |id| enter(id) }

      assert sick?("1", "bear")
      assert sick?("1", "dryad"), "land creatures are creatures"
      refute sick?("1", "ring")
      refute sick?("1", "mdfc"), "a land // creature card enters as its front face"
    end

    test "moving a creature around your own battlefield doesn't make it sick again" do
      enter("bear")
      play(I::ApplyRemoveSickness, seat_id: "1", card_instance_id: "bear")
      play(I::ApplyCardMove, seat_id: "1", card_instance_id: "bear", to_zone: "battlefield", x: 40, y: 5)

      refute sick?("1", "bear")
    end

    test "a stolen creature is sick under its new controller" do
      play(I::ApplyCardMove, seat_id: "1", card_instance_id: "opp_bear", to_zone: "battlefield", to_seat_id: "1")

      assert sick?("1", "opp_bear")
    end

    test "creature tokens enter sick" do
      play(I::ApplyCreateCard, seat_id: "1", name: "Grizzly Bears")

      assert state.seat("1").instances.values.select(&:token).all?(&:sick)
    end

    test "can be removed by hand, and goes away when leaving the battlefield" do
      enter("bear")
      play(I::ApplyRemoveSickness, seat_id: "1", card_instance_id: "bear")
      refute sick?("1", "bear")

      enter("ring")
      play(I::ApplyCardMove, seat_id: "1", card_instance_id: "bear", to_zone: "hand")
      refute sick?("1", "bear")
    end

    test "a new turn cures the player's creatures" do
      enter("bear")
      play(I::ApplyNewTurn, seat_id: "1")

      refute sick?("1", "bear")
    end

    test "passing the turn cures the creatures of the player whose turn begins" do
      enter("bear")
      play(I::ApplyCardMove, seat_id: "2", card_instance_id: "opp_bear", to_zone: "graveyard")
      play(I::ApplyCardMove, seat_id: "2", card_instance_id: "opp_bear", to_zone: "battlefield")
      assert sick?("2", "opp_bear")

      play(I::ApplyPassTurn, seat_id: "1")

      refute sick?("2", "opp_bear")
      assert sick?("1", "bear"), "the player who passed keeps theirs until their next turn"
    end
  end

  class RestartVoteTest < ActiveSupport::TestCase
    include GameTestHelper

    PickLast = Struct.new(:unused) { def rand(n) = n - 1 }
    DECK = { "format" => "commander", "library" => (1..99).to_a, "command" => [ 500 ] }.freeze

    setup do
      played = Table::Entities::SeatState.deal(seat_id: "1", deck: DECK)
        .with(life_total: 12, hand_kept: true, commander_damage: { "x" => 9 })
      build_game(seats: { "1" => played, "2" => Table::Entities::SeatState.deal(seat_id: "2", deck: DECK) }, active_seat_id: "1")
    end

    def vote(seat_id, answer)
      call_interaction(Table::Interactions::ApplyRestartVote,
                       deps: { table_repo: table_repo, state_store: state_store, broadcaster: broadcaster, card_catalog: catalog, rng: PickLast.new },
                       table_slug: "table-1", seat_id: seat_id, answer: answer)
    end

    test "a request waits for everyone else, and everyone sees who is pending" do
      vote("1", "request")

      assert_equal %w[1], state.restart_vote["accepted"]
      assert_equal 12, state.seat("1").life_total, "nothing restarted yet"
      assert_equal %w[2], broadcaster.view_for("2")["restart_vote"]["pending"]
    end

    test "once everyone accepts, every seat is redealt from its deck and the first player is drawn" do
      vote("1", "request")
      vote("2", "accept")

      assert_nil state.restart_vote
      %w[1 2].each do |seat_id|
        seat = state.seat(seat_id)
        assert_equal [ 7, 92, 1, 40 ], [ seat.zones["hand"].size, seat.zones["library"].size, seat.zones["command"].size, seat.life_total ]
        refute seat.hand_kept
        assert_empty seat.commander_damage
      end
      assert_equal [ 1, "2" ], [ state.turn_number, state.active_seat_id ], "the stubbed draw picks the last seat"
      assert_equal [ 1, "2" ], [ state.round, state.first_seat_id ], "the drawn player opens round 1"
      assert_equal [ [ "restart", { "first_seat_id" => "2" } ] ], state.log.map { |e| [ e.event_type, e.payload ] }
    end

    test "any refusal cancels the vote" do
      vote("1", "request")
      vote("2", "decline")

      assert_nil state.restart_vote
      assert_equal 12, state.seat("1").life_total
      assert_equal "restart_declined", last_log.event_type
    end

    test "a player alone at the table restarts right away" do
      build_game(seats: { "1" => Table::Entities::SeatState.deal(seat_id: "1", deck: DECK).with(life_total: 3) })

      vote("1", "request")

      assert_equal 40, state.seat("1").life_total
    end

    test "seats dealt before decks were remembered are redealt from the cards they own" do
      legacy = seat_state(
        hand: { "h" => card(10, owner: "2") },
        library: (1..5).to_h { |i| [ "l#{i}", card(100 + i, owner: "2") ] },
        command: { "cmd" => card(500, owner: "2") },
        battlefield: { "tok" => card(900, owner: "2", token: true), "stolen" => card(1, owner: "1") }
      )
      mine = Table::Entities::SeatState.deal(seat_id: "1", deck: DECK)
      mine = mine.with_card("borrowed", card(11, owner: "2"), zone: "battlefield")
      build_game(seats: { "1" => mine, "2" => legacy })

      vote("1", "request")
      vote("2", "accept")

      redealt = state.seat("2")
      cards = ->(zone) { redealt.zones[zone].map { |id| redealt.instances[id].card_id } }
      assert_equal [ 10, 11, 101, 102, 103, 104, 105 ].sort, (cards.("hand") + cards.("library")).sort
      assert_equal [ 500 ], cards.("command")
      assert redealt.instances[redealt.zones["command"].first].commander
      assert_equal({ "format" => "commander", "library" => [ 10, 11, 101, 102, 103, 104, 105 ].sort, "command" => [ 500 ] },
                   redealt.deck.merge("library" => redealt.deck["library"].sort))
      assert_equal 40, redealt.life_total
      assert_equal 100, state.seat("1").zones.values.sum(&:size), "the stolen card went back to its owner's deck"
    end

    test "rejects answers without a pending vote, double requests and seats not in the game" do
      assert_equal :not_found, vote("2", "accept").failure.first
      vote("1", "request")
      assert_equal :validation_error, vote("2", "request").failure.first
      assert_equal :forbidden, vote("9", "accept").failure.first
    end
  end

  class StartGameTest < ActiveSupport::TestCase
    include GameTestHelper

    setup { build_game(seats: { "1" => nil, "2" => nil }) }

    def deal(seat_id, format:)
      deck = Table::Entities::ValidatedDeck.new(format: format, library_card_ids: (1..99).to_a, command_card_ids: [ 500 ])
      play(Table::Interactions::StartGame, seat_id: seat_id, validated_deck: deck)
    end

    test "deals 7, puts the commander in the command zone and starts at 40 life" do
      deal("1", format: "commander")

      assert_equal 7, zone("1", "hand").size
      assert_equal 92, zone("1", "library").size
      assert_equal 1, zone("1", "command").size
      assert_equal 40, state.seat("1").life_total
      refute state.seat("1").hand_kept
      assert state.seat("1").instances[zone("1", "command").first].commander
      refute state.seat("1").instances[zone("1", "library").first].commander
      assert(state.seat("1").instances.values.all? { |i| i.owner_seat_id == "1" })
    end

    test "other formats start at 20" do
      deal("1", format: "standard")

      assert_equal 20, state.seat("1").life_total
    end

    test "remembers the deck it dealt, for restarts" do
      deal("1", format: "commander")

      assert_equal({ "format" => "commander", "library" => (1..99).to_a, "command" => [ 500 ] }, state.seat("1").deck)
    end

    test "the first seat dealt in becomes the active player, and opens the game" do
      deal("2", format: "commander")
      deal("1", format: "commander")

      assert_equal [ "2", "2" ], [ state.active_seat_id, state.first_seat_id ]
    end
  end
end
