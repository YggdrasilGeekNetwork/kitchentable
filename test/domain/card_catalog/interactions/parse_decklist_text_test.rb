require "test_helper"

class ParseDecklistTextTest < ActiveSupport::TestCase
  test "parses simple quantity + name lines" do
    result = CardCatalog::Interactions::ParseDecklistText.call(text: "4 Lightning Bolt\n1 Sol Ring")
    assert result.success?

    entries = result.value![:entries]
    assert_equal 2, entries.size
    assert_equal "Lightning Bolt", entries[0].raw_name
    assert_equal 4, entries[0].quantity
  end

  test "parses the MTGA export suffix" do
    result = CardCatalog::Interactions::ParseDecklistText.call(text: "1 Lightning Bolt (LEA) 161")
    entry = result.value![:entries].first

    assert_equal "Lightning Bolt", entry.raw_name
    assert_equal 1, entry.quantity
  end

  test "section headers switch which zone following lines belong to; Commander stays in the main list" do
    text = <<~DECK
      Commander:
      1 Thelon of Havenwood

      Deck:
      1 Sol Ring

      Sideboard:
      1 Pithing Needle
    DECK

    entries = CardCatalog::Interactions::ParseDecklistText.call(text: text).value![:entries]

    assert_equal :main, entries.find { |e| e.raw_name == "Thelon of Havenwood" }.section
    assert_equal :main, entries.find { |e| e.raw_name == "Sol Ring" }.section
    assert_equal :sideboard, entries.find { |e| e.raw_name == "Pithing Needle" }.section
  end

  test "skips blank lines and comments, warns on unparseable lines" do
    result = CardCatalog::Interactions::ParseDecklistText.call(text: "// a comment\n\nnot a valid line\n2 Mountain")

    assert_equal 1, result.value![:entries].size
    assert_equal 1, result.value![:warnings].size
    assert_match(/unparseable/, result.value![:warnings].first[:message])
  end
end
