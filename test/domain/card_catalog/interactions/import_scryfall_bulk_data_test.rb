require "test_helper"

class ImportScryfallBulkDataTest < ActiveSupport::TestCase
  Importer = CardCatalog::Interactions::ImportScryfallBulkData

  class RecordingCatalog < CardCatalog::Ports::CardCatalogPort
    attr_reader :upserted

    def initialize = @upserted = []
    def upsert_bulk(attrs_list) = @upserted.concat(attrs_list)
  end

  # Serves canned bodies by URL, mimicking Scryfall's bulk-data index, the gzipped
  # oracle dump, and the paginated flavor-name search.
  class FakeScryfall
    DUMP_URL = "https://data.scryfall.io/oracle-cards.jsonl.gz"
    PAGE_2_URL = "https://api.scryfall.com/cards/search?page=2"

    def initialize(cards:, flavor_pages:)
      @bodies = {
        Importer::BULK_DATA_INDEX_URL => { data: [ { type: "oracle_cards", jsonl_download_uri: DUMP_URL } ] }.to_json,
        DUMP_URL => ActiveSupport::Gzip.compress(cards.map(&:to_json).join("\n"))
      }
      flavor_pages.each_with_index do |printings, i|
        url = i.zero? ? Importer::FLAVOR_NAME_SEARCH_URL : PAGE_2_URL
        last = i == flavor_pages.size - 1
        @bodies[url] = { data: printings, has_more: !last, next_page: (PAGE_2_URL unless last) }.to_json
      end
    end

    def fetch(url) = @bodies.fetch(url)
  end

  def import_from_file(*raw_cards)
    catalog = RecordingCatalog.new
    Tempfile.create([ "oracle", ".jsonl" ]) do |file|
      file.write(raw_cards.map(&:to_json).join("\n"))
      file.flush
      call_interaction(Importer, deps: { catalog: catalog }, source: file.path)
    end
    catalog.upserted
  end

  def import_live(cards:, flavor_pages:)
    catalog = RecordingCatalog.new
    result = call_interaction(Importer, deps: { catalog: catalog, fetcher: FakeScryfall.new(cards:, flavor_pages:) })
    assert result.success?, result.inspect
    catalog.upserted.index_by { |c| c[:name] }
  end

  def oracle(name, layout: "normal", **extra)
    { "oracle_id" => SecureRandom.uuid, "name" => name, "layout" => layout, **extra }
  end

  test "keeps each face of a double-faced card, with its own images" do
    card = import_from_file(oracle(
      "Elesh Norn // The Argent Etchings", layout: "transform",
      "card_faces" => [
        { "name" => "Elesh Norn", "mana_cost" => "{2}{W}{W}", "type_line" => "Legendary Creature — Phyrexian Praetor",
          "oracle_text" => "Vigilance", "image_uris" => { "normal" => "https://img/front.jpg" }, "artist" => "ignored" },
        { "name" => "The Argent Etchings", "mana_cost" => "", "type_line" => "Enchantment — Saga",
          "oracle_text" => "(As this Saga enters...)", "image_uris" => { "normal" => "https://img/back.jpg" } }
      ]
    )).first

    assert_equal "eleshnorn", card[:front_face_name_normalized]
    assert_equal({}, card[:image_uris])
    assert_equal [ "Elesh Norn", "The Argent Etchings" ], card[:card_faces].map { |f| f["name"] }
    assert_equal "https://img/back.jpg", card[:card_faces].last["image_uris"]["normal"]
    refute card[:card_faces].first.key?("artist")
  end

  test "keeps power, toughness and loyalty, on the card and on each face" do
    creature = import_from_file(oracle("Deepglow Skate", "power" => "3", "toughness" => "3")).first
    walker = import_from_file(oracle(
      "Nissa, Who Shakes the World", "loyalty" => "5",
      "card_faces" => [ { "name" => "Front", "power" => "*", "toughness" => "1+*", "loyalty" => nil } ]
    )).first

    assert_equal %w[3 3], creature.values_at(:power, :toughness)
    assert_equal "5", walker[:loyalty]
    assert_equal %w[* 1+*], walker[:card_faces].first.values_at("power", "toughness")
  end

  test "split and adventure faces are kept without images of their own" do
    card = import_from_file(oracle(
      "Bonecrusher Giant // Stomp", layout: "adventure",
      "image_uris" => { "normal" => "https://img/giant.jpg" },
      "card_faces" => [ { "name" => "Bonecrusher Giant" }, { "name" => "Stomp" } ]
    )).first

    assert_equal "bonecrushergiant", card[:front_face_name_normalized]
    assert_equal [ {}, {} ], card[:card_faces].map { |f| f["image_uris"] }
    assert_equal "https://img/giant.jpg", card[:image_uris]["normal"]
  end

  test "a card with more than two names uses the first as its front face" do
    card = import_from_file(oracle("Who // What // When // Where // Why", layout: "split")).first

    assert_equal "who", card[:front_face_name_normalized]
    assert_equal "whowhatwhenwherewhy", card[:name_normalized]
  end

  test "single-faced cards get no faces and an identical front-face name" do
    card = import_from_file(oracle("Sol Ring")).first

    assert_equal [], card[:card_faces]
    assert_equal "solring", card[:front_face_name_normalized]
    assert_equal [], card[:alternate_names_normalized]
  end

  test "art series cards are not imported" do
    names = import_from_file(oracle("Sheoldred // Sheoldred", layout: "art_series"), oracle("Sol Ring")).map { |c| c[:name] }

    assert_equal [ "Sol Ring" ], names
  end

  test "a local dump keeps the flavor names it contains, on the card or its faces" do
    card = import_from_file(oracle(
      "Delver of Secrets // Insectile Aberration", layout: "transform",
      "card_faces" => [ { "name" => "Delver of Secrets", "flavor_name" => "Front Alias" },
                        { "name" => "Insectile Aberration", "flavor_name" => "Back Alias" } ]
    )).first

    assert_equal %w[frontalias backalias], card[:alternate_names_normalized]
  end

  test "live sync collects flavor names from every search page onto the matching card" do
    zilortha = oracle("Zilortha, Strength Incarnate")
    growth = oracle("Abundant Growth")
    sol_ring = oracle("Sol Ring")

    cards = import_live(
      cards: [ zilortha, growth, sol_ring ],
      flavor_pages: [
        [ { "oracle_id" => zilortha["oracle_id"], "flavor_name" => "Godzilla, King of the Monsters" },
          { "oracle_id" => growth["oracle_id"], "flavor_name" => "Abundant Groot" } ],
        [ { "oracle_id" => growth["oracle_id"], "flavor_name" => "Abundant Groot" },
          { "oracle_id" => growth["oracle_id"], "flavor_name" => "Another Growth Alias" } ]
      ]
    )

    assert_equal [ "godzillakingofthemonsters" ], cards["Zilortha, Strength Incarnate"][:alternate_names_normalized]
    assert_equal %w[abundantgroot anothergrowthalias], cards["Abundant Growth"][:alternate_names_normalized]
    assert_equal [], cards["Sol Ring"][:alternate_names_normalized]
  end

  test "live sync reads the oracle id from the faces of reversible printings" do
    delver = oracle("Delver of Secrets // Insectile Aberration", layout: "transform")

    cards = import_live(
      cards: [ delver ],
      flavor_pages: [ [ { "card_faces" => [ { "oracle_id" => delver["oracle_id"], "flavor_name" => "Reversible Alias" },
                                            { "oracle_id" => delver["oracle_id"] } ] } ] ]
    )

    assert_equal [ "reversiblealias" ], cards["Delver of Secrets // Insectile Aberration"][:alternate_names_normalized]
  end
end
