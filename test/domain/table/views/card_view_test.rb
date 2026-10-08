require "test_helper"

class CardViewTest < ActiveSupport::TestCase
  Card = Struct.new(:id, :name, :mana_cost, :type_line, :oracle_text, :power, :toughness, :loyalty, :image_uris, :card_faces,
                    keyword_init: true)

  def uris(name) = { "normal" => "https://img/#{name}.jpg", "art_crop" => "https://art/#{name}.jpg" }

  test "a single-faced creature has one face with stats, image and art crop" do
    card = Card.new(id: 1, name: "Deepglow Skate", mana_cost: "{4}{U}", type_line: "Creature — Fish", oracle_text: "...",
                    power: "3", toughness: "3", image_uris: uris("skate"), card_faces: [])

    view = Table::Views::CardView.call(card)

    refute view["double_faced"]
    assert_equal [ { "name" => "Deepglow Skate", "mana_cost" => "{4}{U}", "type_line" => "Creature — Fish", "oracle_text" => "...",
                     "power" => "3", "toughness" => "3", "loyalty" => nil,
                     "image" => "https://img/skate.jpg", "art" => "https://art/skate.jpg" } ], view["faces"]
  end

  test "a double-faced card has an image, art and stats per face" do
    card = Card.new(id: 2, name: "Delver of Secrets // Insectile Aberration", image_uris: {}, card_faces: [
      { "name" => "Delver of Secrets", "type_line" => "Creature — Human Wizard", "power" => "1", "toughness" => "1", "image_uris" => uris("front") },
      { "name" => "Insectile Aberration", "type_line" => "Creature — Human Insect", "power" => "3", "toughness" => "2", "image_uris" => uris("back") }
    ])

    view = Table::Views::CardView.call(card)

    assert view["double_faced"]
    assert_equal %w[https://art/front.jpg https://art/back.jpg], view["faces"].map { |f| f["art"] }
    assert_equal %w[3 2], view["faces"].last.values_at("power", "toughness")
  end

  test "split and adventure faces share the card's image" do
    card = Card.new(id: 3, name: "Bonecrusher Giant // Stomp", image_uris: uris("giant"), card_faces: [
      { "name" => "Bonecrusher Giant", "type_line" => "Creature — Giant", "power" => "4", "toughness" => "3" },
      { "name" => "Stomp", "type_line" => "Instant — Adventure" }
    ])

    view = Table::Views::CardView.call(card)

    refute view["double_faced"]
    assert_equal [ "https://img/giant.jpg" ] * 2, view["faces"].map { |f| f["image"] }
    assert_equal "Creature — Giant", view["faces"].first["type_line"]
  end
end
