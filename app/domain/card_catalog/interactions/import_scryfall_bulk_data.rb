require "zlib"
require "stringio"

module CardCatalog
  module Interactions
    class ImportScryfallBulkData < Shared::BaseInteraction
      BULK_DATA_INDEX_URL = "https://api.scryfall.com/bulk-data"
      BATCH_SIZE = 1000
      # Oracle cards is a ~25MB gzip download as of writing (~150MB decompressed JSONL).
      # Trusted, hardcoded source — not the small cap used for arbitrary decklist links.
      MAX_DOWNLOAD_BYTES = 200.megabytes
      # Flavor names live on individual printings, which the oracle_cards dump (one
      # printing per card) mostly lacks — so they're collected from a search instead
      # (~700 printings, a handful of pages). Scryfall asks for 50–100ms between calls.
      FLAVOR_NAME_SEARCH_URL = "https://api.scryfall.com/cards/search?q=has%3Aflavorname&unique=prints"
      SEARCH_PAGE_DELAY = 0.1

      def initialize(
        catalog: Persistence::Postgres::CardCatalogRepository.new,
        fetcher: Http::SafeUrlFetcher.new(max_bytes: MAX_DOWNLOAD_BYTES)
      )
        @catalog = catalog
        @fetcher = fetcher
      end

      # `source:` lets tests/rake tasks inject a local fixture/dump path (plain JSON
      # array or .jsonl) instead of hitting the real Scryfall bulk-data endpoint. A
      # local dump is used as-is: only the flavor names it already contains are kept.
      def call(source: nil)
        payload = step fetch_payload(source)
        cards = step parse(payload)
        flavor_names = source ? {} : step(fetch_flavor_names)
        step upsert(add_alternate_names(cards, flavor_names))
        Success(imported: cards.size)
      end

      private

      # Scryfall's bulk-data index entries expose a `jsonl_download_uri` (gzip-
      # compressed JSON Lines, one card object per line) — there is no plain
      # uncompressed `download_uri` any more.
      def fetch_payload(source)
        return Success(File.read(source)) if source

        index = JSON.parse(@fetcher.fetch(BULK_DATA_INDEX_URL))
        entry = index["data"]&.find { |d| d["type"] == "oracle_cards" }
        return Failure[:not_found, "oracle_cards bulk data entry not found"] unless entry

        compressed = @fetcher.fetch(entry["jsonl_download_uri"])
        Success(Zlib::GzipReader.new(StringIO.new(compressed)).read)
      rescue Http::SafeUrlFetcher::UnsafeUrlError => e
        Failure[:fetch_error, e.message]
      end

      def parse(payload)
        cards = payload.each_line.filter_map { |line|
          line = line.strip
          next if line.empty?

          raw = JSON.parse(line)
          next if raw["oracle_id"].nil? # guards against one bad row poisoning a whole upsert batch
          next if raw["layout"] == "art_series" # collectible art cards, never played

          map_card(raw)
        }
        Success(cards)
      rescue JSON::ParserError => e
        Failure[:parse_error, e.message]
      end

      def map_card(raw)
        {
          scryfall_oracle_id: raw["oracle_id"],
          name: raw["name"],
          name_normalized: normalize(raw["name"]),
          front_face_name_normalized: normalize(raw["name"].to_s.split(" // ").first),
          mana_cost: raw["mana_cost"],
          cmc: raw["cmc"],
          type_line: raw["type_line"],
          oracle_text: raw["oracle_text"],
          power: raw["power"],
          toughness: raw["toughness"],
          loyalty: raw["loyalty"],
          colors: raw["colors"] || [],
          color_identity: raw["color_identity"] || [],
          legalities: raw["legalities"] || {},
          image_uris: raw["image_uris"] || {},
          card_faces: map_faces(raw["card_faces"]),
          related_tokens: related_tokens(raw),
          alternate_names_normalized: flavor_names_of(raw),
          layout: raw["layout"],
          set_code: raw["set"],
          collector_number: raw["collector_number"],
          rarity: raw["rarity"],
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      # Double-faced cards keep their images here instead of in the top-level
      # `image_uris`; split/adventure faces have none and share the card's image.
      def map_faces(faces)
        Array(faces).map { |face|
          face.slice("name", "mana_cost", "type_line", "oracle_text", "power", "toughness", "loyalty").merge(
            "image_uris" => face["image_uris"] || {}
          )
        }
      end

      # The tokens and emblems a card can make (Scryfall's all_parts, minus the card
      # itself and non-token parts like meld pairs).
      def related_tokens(raw)
        Array(raw["all_parts"])
          .select { |part| part["component"] == "token" && part["name"] != raw["name"] }
          .map { |part| part.slice("name", "type_line") }
          .uniq
      end

      # oracle_id => normalized flavor names, from every printing that has one.
      def fetch_flavor_names
        names = Hash.new { |h, k| h[k] = [] }
        url = FLAVOR_NAME_SEARCH_URL

        while url
          page = JSON.parse(@fetcher.fetch(url))
          page["data"].each do |printing|
            oracle_id = printing["oracle_id"] || printing.dig("card_faces", 0, "oracle_id")
            names[oracle_id] |= flavor_names_of(printing) if oracle_id
          end

          url = page["has_more"] ? page["next_page"] : nil
          sleep(SEARCH_PAGE_DELAY) if url
        end

        Success(names)
      rescue Http::SafeUrlFetcher::UnsafeUrlError, JSON::ParserError => e
        Failure[:fetch_error, "flavor names: #{e.message}"]
      end

      def flavor_names_of(raw)
        [ raw["flavor_name"], *Array(raw["card_faces"]).map { |f| f["flavor_name"] } ]
          .compact.map { |n| normalize(n) }.uniq
      end

      def add_alternate_names(cards, flavor_names)
        cards.map { |card|
          extra = flavor_names.fetch(card[:scryfall_oracle_id], [])
          card.merge(alternate_names_normalized: card[:alternate_names_normalized] | extra)
        }
      end

      def normalize(name) = name.to_s.downcase.gsub(/[^a-z0-9]/, "")

      def upsert(cards)
        cards.each_slice(BATCH_SIZE) { |batch| @catalog.upsert_bulk(batch) }
        Success(true)
      rescue => e
        Failure[:persistence_error, e.message]
      end
    end
  end
end
