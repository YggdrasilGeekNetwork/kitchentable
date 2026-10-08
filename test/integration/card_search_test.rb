require "test_helper"

class CardSearchTest < ActionDispatch::IntegrationTest
  test "returns matching cards as JSON" do
    Card.create!(scryfall_oracle_id: SecureRandom.uuid, name: "Clue", layout: "token", type_line: "Token Artifact — Clue")

    get card_search_path, params: { q: "clu" }

    assert_response :success
    assert_equal [ "Clue" ], response.parsed_body.map { |c| c["name"] }
  end
end
