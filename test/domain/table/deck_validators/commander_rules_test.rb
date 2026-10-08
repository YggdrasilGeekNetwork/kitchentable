require "test_helper"

class CommanderRulesTest < ActiveSupport::TestCase
  setup do
    @catalog = Fakes::FakeCardCatalog.new
    @commander = @catalog.register(name: "Thelon of Havenwood", type_line: "Legendary Creature", color_identity: %w[G])
    @ok_card = @catalog.register(name: "Sol Ring", type_line: "Artifact", color_identity: [])
    @off_color_card = @catalog.register(name: "Lightning Bolt", type_line: "Instant", color_identity: %w[R])
    @banned_card = @catalog.register(name: "Black Lotus", type_line: "Artifact", color_identity: [], legalities: { "commander" => "banned" })
  end

  Entry = Struct.new(:section, :quantity, keyword_init: true)

  def resolved_row(card, section:, quantity: 1)
    { entry: Entry.new(section: section, quantity: quantity), card: card }
  end

  test "valid 100-card deck with one commander passes" do
    deck_rows = Array.new(99) { @ok_card } # not realistic singleton-wise, overridden below
    resolved = [ resolved_row(@commander, section: :commander) ] +
      [ resolved_row(@ok_card, section: :main, quantity: 1) ] +
      (1..98).map { |i| resolved_row(@catalog.register(name: "Filler #{i}"), section: :main) }

    result = call_interaction(Table::DeckValidators::CommanderRules, resolved, deps: { catalog: @catalog })

    assert result.success?, result.failure.inspect
    deck = result.value!
    assert_equal 99, deck.library_card_ids.size
    assert_equal [ @commander.id ], deck.command_card_ids
  end

  test "rejects a deck without exactly one commander" do
    resolved = (1..100).map { |i| resolved_row(@catalog.register(name: "Card #{i}"), section: :main) }

    result = call_interaction(Table::DeckValidators::CommanderRules, resolved, deps: { catalog: @catalog })

    assert result.failure?
    assert result.failure.last.any? { |e| e[:type] == "commander_count" }
  end

  test "rejects duplicate non-land cards (singleton)" do
    resolved = [ resolved_row(@commander, section: :commander) ] +
      [ resolved_row(@ok_card, section: :main, quantity: 2) ] +
      (1..97).map { |i| resolved_row(@catalog.register(name: "Card #{i}"), section: :main) }

    result = call_interaction(Table::DeckValidators::CommanderRules, resolved, deps: { catalog: @catalog })

    assert result.failure?
    assert result.failure.last.any? { |e| e[:type] == "singleton" }
  end

  test "rejects cards outside the commander's color identity" do
    resolved = [ resolved_row(@commander, section: :commander) ] +
      [ resolved_row(@off_color_card, section: :main) ] +
      (1..98).map { |i| resolved_row(@catalog.register(name: "Card #{i}"), section: :main) }

    result = call_interaction(Table::DeckValidators::CommanderRules, resolved, deps: { catalog: @catalog })

    assert result.failure?
    assert result.failure.last.any? { |e| e[:type] == "color_identity" }
  end

  test "rejects banned cards" do
    resolved = [ resolved_row(@commander, section: :commander) ] +
      [ resolved_row(@banned_card, section: :main) ] +
      (1..98).map { |i| resolved_row(@catalog.register(name: "Card #{i}"), section: :main) }

    result = call_interaction(Table::DeckValidators::CommanderRules, resolved, deps: { catalog: @catalog })

    assert result.failure?
    assert result.failure.last.any? { |e| e[:type] == "legality" }
  end

  test "two commanders share the deck: 98 cards plus both" do
    partner = @catalog.register(name: "Kraum, Ludevic's Opus", type_line: "Legendary Creature", color_identity: %w[U R])
    resolved = [ resolved_row(@commander, section: :commander), resolved_row(partner, section: :commander) ] +
      (1..98).map { |i| resolved_row(@catalog.register(name: "Card #{i}"), section: :main) }

    result = call_interaction(Table::DeckValidators::CommanderRules, resolved, deps: { catalog: @catalog })

    assert result.success?, result.failure.inspect
    assert_equal [ @commander.id, partner.id ], result.value!.command_card_ids
  end

  test "with two commanders, the color identity is the union of both" do
    partner = @catalog.register(name: "Kraum, Ludevic's Opus", type_line: "Legendary Creature", color_identity: %w[U R])
    resolved = [ resolved_row(@commander, section: :commander), resolved_row(partner, section: :commander),
                 resolved_row(@off_color_card, section: :main) ] +
      (1..97).map { |i| resolved_row(@catalog.register(name: "Card #{i}"), section: :main) }

    result = call_interaction(Table::DeckValidators::CommanderRules, resolved, deps: { catalog: @catalog })

    assert result.success?, result.failure.inspect
  end

  test "rejects more than two commanders" do
    extra = (1..2).map { |i| @catalog.register(name: "Extra Commander #{i}", type_line: "Legendary Creature") }
    resolved = [ resolved_row(@commander, section: :commander), *extra.map { |c| resolved_row(c, section: :commander) } ] +
      (1..97).map { |i| resolved_row(@catalog.register(name: "Card #{i}"), section: :main) }

    result = call_interaction(Table::DeckValidators::CommanderRules, resolved, deps: { catalog: @catalog })

    assert result.failure?
    assert result.failure.last.any? { |e| e[:type] == "commander_count" }
  end

  test "rejects the same card chosen as both commanders" do
    resolved = [ resolved_row(@commander, section: :commander), resolved_row(@commander, section: :commander) ] +
      (1..98).map { |i| resolved_row(@catalog.register(name: "Card #{i}"), section: :main) }

    result = call_interaction(Table::DeckValidators::CommanderRules, resolved, deps: { catalog: @catalog })

    assert result.failure?
    assert result.failure.last.any? { |e| e[:type] == "singleton" }
  end
end
