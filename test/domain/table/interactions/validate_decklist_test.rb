require "test_helper"

class ValidateDecklistTest < ActiveSupport::TestCase
  setup do
    @catalog = Fakes::FakeCardCatalog.new
    @atraxa = @catalog.register(name: "Atraxa, Praetors' Voice", type_line: "Legendary Creature", color_identity: %w[W U B G])
    @fillers = (1..99).map { |i| @catalog.register(name: "Filler #{i}") }
  end

  def validate(raw_text, format: "commander", commanders: [])
    call_interaction(Table::Interactions::ValidateDecklist, deps: { catalog: @catalog },
                     raw_text: raw_text, format: format, commander_names: commanders)
  end

  def list(names) = names.map { |n| "1 #{n}" }.join("\n")

  test "the commander comes from its own field, with a 99-card list" do
    result = validate(list(@fillers.map(&:name)), commanders: [ "Atraxa, Praetors' Voice" ])

    assert result.success?, result.inspect
    assert_equal [ @atraxa.id ], result.value!.command_card_ids
    assert_equal 99, result.value!.library_card_ids.size
  end

  test "a 100-card list that also includes the commander counts it only once" do
    raw = list([ "Atraxa, Praetors' Voice", *@fillers.map(&:name) ])

    result = validate(raw, commanders: [ "Atraxa, Praetors' Voice" ])

    assert result.success?, result.inspect
    assert_equal [ @atraxa.id ], result.value!.command_card_ids
    refute_includes result.value!.library_card_ids, @atraxa.id
    assert_equal 99, result.value!.library_card_ids.size
  end

  test "the commander field accepts any name form the catalog resolves" do
    result = validate(list(@fillers.map(&:name)), commanders: [ "  atraxa praetors voice  " ])

    assert result.success?, result.inspect
    assert_equal [ @atraxa.id ], result.value!.command_card_ids
  end

  test "a Commander deck without the field filled in is rejected" do
    result = validate(list([ "Atraxa, Praetors' Voice", *@fillers.map(&:name) ]), commanders: [ " ", "" ])

    assert result.failure?
    assert_equal "commander_missing", result.failure.last.first[:type]
  end

  test "a Commander header inside the list does not choose the commander" do
    raw = "Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n#{list(@fillers.first(98).map(&:name))}"

    result = validate(raw, commanders: [])

    assert result.failure?
    assert_equal "commander_missing", result.failure.last.first[:type]
  end

  test "an unknown commander name is reported like any unknown card" do
    result = validate(list(@fillers.map(&:name)), commanders: [ "Not A Real Card" ])

    assert result.failure?
    assert_equal [ "Unknown card: \"Not A Real Card\"" ], result.failure.last.map { |e| e[:message] }
  end

  test "Standard ignores the commander field" do
    @catalog.register(name: "Island", type_line: "Basic Land — Island")

    result = validate("60 Island", format: "standard", commanders: [ "Atraxa, Praetors' Voice" ])

    assert result.success?, result.inspect
    assert_equal 60, result.value!.library_card_ids.size
  end

  # --- Partner / Background pairs ---

  def register_pair
    @tymna = @catalog.register(name: "Tymna the Weaver", type_line: "Legendary Creature", color_identity: %w[W B])
    @thrasios = @catalog.register(name: "Thrasios, Triton Hero", type_line: "Legendary Creature", color_identity: %w[G U])
  end

  test "a second commander goes to the command zone with a 98-card list" do
    register_pair

    result = validate(list(@fillers.first(98).map(&:name)), commanders: [ "Tymna the Weaver", "Thrasios, Triton Hero" ])

    assert result.success?, result.inspect
    assert_equal [ @tymna.id, @thrasios.id ], result.value!.command_card_ids
    assert_equal 98, result.value!.library_card_ids.size
  end

  test "a 100-card list that includes both commanders counts each only once" do
    register_pair
    raw = list([ "Tymna the Weaver", "Thrasios, Triton Hero", *@fillers.first(98).map(&:name) ])

    result = validate(raw, commanders: [ "Tymna the Weaver", "Thrasios, Triton Hero" ])

    assert result.success?, result.inspect
    assert_equal 98, result.value!.library_card_ids.size
    refute_includes result.value!.library_card_ids, @tymna.id
    refute_includes result.value!.library_card_ids, @thrasios.id
  end

  test "a Background works as the second commander" do
    wilson = @catalog.register(name: "Wilson, Refined Grizzly", type_line: "Legendary Creature", color_identity: %w[G])
    background = @catalog.register(name: "Raised by Giants", type_line: "Legendary Enchantment — Background", color_identity: %w[G])

    result = validate(list(@fillers.first(98).map(&:name)), commanders: [ "Wilson, Refined Grizzly", "Raised by Giants" ])

    assert result.success?, result.inspect
    assert_equal [ wilson.id, background.id ], result.value!.command_card_ids
  end

  test "only the second field filled in still counts as one commander" do
    result = validate(list(@fillers.map(&:name)), commanders: [ "", "Atraxa, Praetors' Voice" ])

    assert result.success?, result.inspect
    assert_equal [ @atraxa.id ], result.value!.command_card_ids
  end
end
