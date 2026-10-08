require "test_helper"

class FetchDeckTokensTest < ActiveSupport::TestCase
  include GameTestHelper

  setup do
    @catalog = Fakes::FakeCardCatalog.new
    @krenko = @catalog.register(name: "Krenko, Mob Boss")
    @goblin = @catalog.register(name: "Goblin", type_line: "Token Creature — Goblin", power: "1", toughness: "1")
    @catalog.link_tokens(@krenko, @goblin)
  end

  def tokens(seat_id) = call_interaction(Table::Interactions::FetchDeckTokens, deps: { state_store: state_store, card_catalog: catalog },
                                         table_slug: "table-1", seat_id: seat_id).value!

  test "suggests the tokens the seat's deck can make" do
    build_game(seats: { "1" => Table::Entities::SeatState.deal(seat_id: "1", deck: { "format" => "commander", "library" => [ @krenko.id ], "command" => [] }) })

    assert_equal [ { "id" => @goblin.id, "name" => "Goblin", "type_line" => "Token Creature — Goblin", "power" => "1", "toughness" => "1" } ], tokens("1")
  end

  test "seats dealt before decks were remembered use the cards they own" do
    build_game(seats: { "1" => seat_state(battlefield: { "k" => card(@krenko.id, owner: "1") }) })

    assert_equal [ "Goblin" ], tokens("1").map { |t| t["name"] }
  end

  test "a seat not in the game gets nothing" do
    build_game(seats: { "1" => seat_state })

    assert_empty tokens("2")
  end
end
