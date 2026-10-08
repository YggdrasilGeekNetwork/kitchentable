require "test_helper"

# Decklists name cards however the exporting site or the player wrote them, so every
# multi-name card shape has to resolve: multi-face cards by full or front-face name,
# and alternate printed names (Scryfall flavor names) by that name.
class CardCatalogRepositoryTest < ActiveSupport::TestCase
  setup { @repo = Persistence::Postgres::CardCatalogRepository.new }

  def create_card(name, layout: "normal", alternate_names: [])
    Card.create!(
      scryfall_oracle_id: SecureRandom.uuid, name: name, layout: layout,
      alternate_names_normalized: alternate_names.map { |n| n.downcase.gsub(/[^a-z0-9]/, "") }
    )
  end

  # --- multi-face cards, one per Scryfall layout that joins names with " // " ---

  test "transform: found by front face" do
    card = create_card("Elesh Norn // The Argent Etchings", layout: "transform")

    assert_equal card, @repo.find_by_name("Elesh Norn")
  end

  test "modal double-faced: found by front face" do
    card = create_card("Valakut Awakening // Valakut Stoneforge", layout: "modal_dfc")

    assert_equal card, @repo.find_by_name("Valakut Awakening")
  end

  test "adventure: found by the creature's name" do
    card = create_card("Bonecrusher Giant // Stomp", layout: "adventure")

    assert_equal card, @repo.find_by_name("Bonecrusher Giant")
  end

  test "flip: found by the unflipped name" do
    card = create_card("Akki Lavarunner // Tok-Tok, Volcano Born", layout: "flip")

    assert_equal card, @repo.find_by_name("Akki Lavarunner")
  end

  test "split: found by full name, single-slash spelling, or first half" do
    card = create_card("Fire // Ice", layout: "split")

    assert_equal card, @repo.find_by_name("Fire // Ice")
    assert_equal card, @repo.find_by_name("Fire/Ice")
    assert_equal card, @repo.find_by_name("Fire")
  end

  test "room (split layout): found by the first door" do
    card = create_card("Unholy Annex // Ritual Chamber", layout: "split")

    assert_equal card, @repo.find_by_name("Unholy Annex")
  end

  test "cards with more than two names: found by full name or the first one" do
    card = create_card("Who // What // When // Where // Why", layout: "split")

    assert_equal card, @repo.find_by_name("Who // What // When // Where // Why")
    assert_equal card, @repo.find_by_name("Who")
  end

  test "full name match ignores case and punctuation" do
    card = create_card("Jin-Gitaxias // The Great Synthesis", layout: "transform")

    assert_equal card, @repo.find_by_name("jin gitaxias // the great synthesis")
    assert_equal card, @repo.find_by_name("JIN-GITAXIAS")
  end

  # --- alternate printed names ---

  test "found by an alternate printed name" do
    card = create_card("Zilortha, Strength Incarnate", alternate_names: [ "Godzilla, King of the Monsters" ])

    assert_equal card, @repo.find_by_name("Godzilla, King of the Monsters")
  end

  test "a card with several alternate names is found by each" do
    card = create_card("Abundant Growth", alternate_names: [ "Abundant Groot", "Some Other Name" ])

    assert_equal card, @repo.find_by_name("Abundant Groot")
    assert_equal card, @repo.find_by_name("Some Other Name")
  end

  test "a double-faced card is found by an alternate name of either face" do
    card = create_card("Delver of Secrets // Insectile Aberration", layout: "transform",
                       alternate_names: [ "Front Alias", "Back Alias" ])

    assert_equal card, @repo.find_by_name("Back Alias")
  end

  # --- precedence and exclusions ---

  test "a card's own name beats another card's front face" do
    create_card("Fire // Ice", layout: "split")
    exact = create_card("Fire", layout: "normal")

    assert_equal exact, @repo.find_by_name("Fire")
  end

  test "a card's own name beats another card's alternate name" do
    create_card("Academy Manufactor", alternate_names: [ "Krobus" ])
    exact = create_card("Krobus")

    assert_equal exact, @repo.find_by_name("Krobus")
  end

  test "never resolves a name to an art series card" do
    create_card("Sheoldred // Sheoldred", layout: "art_series")
    card = create_card("Sheoldred // The True Scriptures", layout: "transform")

    assert_equal card, @repo.find_by_name("Sheoldred")
  end

  test "a back face name alone does not match" do
    create_card("Elesh Norn // The Argent Etchings", layout: "transform")

    assert_nil @repo.find_by_name("The Argent Etchings")
  end

  # --- search ---

  test "search lists prefix matches before other matches, skipping art series" do
    create_card("Treasure Map")
    create_card("Buried Treasure")
    create_card("Treasure", layout: "token")
    create_card("Treasure // Treasure", layout: "art_series")

    assert_equal [ "Treasure", "Treasure Map", "Buried Treasure" ], @repo.search("treasure").map(&:name)
  end

  test "search treats LIKE wildcards literally" do
    create_card("Sol Ring")

    assert_empty @repo.search("%")
  end

  # --- deck tokens ---

  def create_token(name, power, toughness, colors, type_line: "Token Creature — #{name}")
    Card.create!(scryfall_oracle_id: SecureRandom.uuid, name: name, layout: "token", type_line: type_line,
                 power: power, toughness: toughness, colors: colors)
  end

  test "deck tokens: picks the same-named token whose size and colors the card's text describes" do
    create_token("Goblin", "2", "2", %w[B])
    red_goblin = create_token("Goblin", "1", "1", %w[R])
    create_token("Goblin", "1", "1", %w[B])
    treasure = create_token("Treasure", nil, nil, [], type_line: "Token Artifact — Treasure")
    krenko = Card.create!(scryfall_oracle_id: SecureRandom.uuid, name: "Krenko, Mob Boss", layout: "normal",
                          oracle_text: "{T}: Create X 1/1 red Goblin creature tokens, where X is the number of Goblins you control.",
                          related_tokens: [ { "name" => "Goblin", "type_line" => "Token Creature — Goblin" } ])
    tithe = Card.create!(scryfall_oracle_id: SecureRandom.uuid, name: "Smothering Tithe", layout: "normal",
                         oracle_text: "...create a Treasure token.", related_tokens: [ { "name" => "Treasure", "type_line" => "Token Artifact — Treasure" } ])

    assert_equal [ red_goblin, treasure ], @repo.deck_tokens([ krenko.id, tithe.id, krenko.id ])
  end

  test "deck tokens: cards that make nothing suggest nothing" do
    assert_empty @repo.deck_tokens([ create_card("Sol Ring").id ])
  end
end
