require "test_helper"

class SearchCardsTest < ActiveSupport::TestCase
  setup do
    @catalog = Fakes::FakeCardCatalog.new
    @treasure = @catalog.register(name: "Treasure", type_line: "Token Artifact — Treasure")
    @catalog.register(name: "Treasure Map", type_line: "Artifact")
  end

  def search(query) = call_interaction(CardCatalog::Interactions::SearchCards, deps: { catalog: @catalog }, query: query)

  test "returns id, name and type line of matches" do
    assert_equal({ "id" => @treasure.id, "name" => "Treasure", "type_line" => "Token Artifact — Treasure" }, search("treas").value!.first)
    assert_equal 2, search("treas").value!.size
  end

  test "ignores queries shorter than two characters" do
    assert_equal [], search(" t ").value!
  end
end
