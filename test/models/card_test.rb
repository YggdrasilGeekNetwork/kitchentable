require "test_helper"

class CardTest < ActiveSupport::TestCase
  def valid_attributes
    {
      scryfall_oracle_id: SecureRandom.uuid,
      name: "Lightning Bolt",
      legalities: { "commander" => "legal" }
    }
  end

  test "normalizes the name on validation" do
    card = Card.new(valid_attributes.merge(name: "Lightning Bolt!"))
    card.valid?

    assert_equal "lightningbolt", card.name_normalized
  end

  test "requires a unique scryfall_oracle_id" do
    oracle_id = SecureRandom.uuid
    Card.create!(valid_attributes.merge(scryfall_oracle_id: oracle_id))
    dup = Card.new(valid_attributes.merge(scryfall_oracle_id: oracle_id, name: "Other Name"))

    assert_not dup.valid?
    assert_includes dup.errors[:scryfall_oracle_id], "has already been taken"
  end

  test "legal_in? reads the legalities jsonb for the given format" do
    card = Card.new(valid_attributes.merge(legalities: { "commander" => "banned", "standard" => "legal" }))

    assert card.legal_in?("standard")
    assert_not card.legal_in?("commander")
  end
end
