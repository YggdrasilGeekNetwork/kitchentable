module Persistence
  module Postgres
    class CardCatalogRepository < CardCatalog::Ports::CardCatalogPort
      # Collectible art cards share names with real cards ("Elesh Norn // Elesh Norn")
      # but can't be played, so they must never win a name lookup.
      UNPLAYABLE_LAYOUTS = %w[art_series].freeze
      TOKEN_LAYOUTS = %w[token double_faced_token emblem].freeze

      # Tried in order, so a card's own name always beats another card's alias:
      #   1. the full Scryfall name ("Elesh Norn // The Argent Etchings")
      #   2. the front face only — how decklists usually list multi-face cards
      #   3. an alternate printed name ("Godzilla, King of the Monsters")
      def find_by_name(name)
        normalized = name.to_s.downcase.gsub(/[^a-z0-9]/, "")
        playable = ::Card.where.not(layout: UNPLAYABLE_LAYOUTS)

        playable.find_by(name_normalized: normalized) ||
          playable.find_by(front_face_name_normalized: normalized) ||
          playable.where("alternate_names_normalized @> ARRAY[?]::varchar[]", normalized).first
      end

      def find_many(ids)
        ::Card.where(id: ids).index_by(&:id)
      end

      def search(query, limit: 12)
        pattern = ::Card.sanitize_sql_like(query.to_s.strip)
        playable = ::Card.where.not(layout: UNPLAYABLE_LAYOUTS).order(:name)
        prefix = playable.where("name ILIKE ?", "#{pattern}%").limit(limit).to_a
        return prefix if prefix.size >= limit

        prefix + playable.where("name ILIKE ?", "%#{pattern}%").where.not(id: prefix.map(&:id)).limit(limit - prefix.size).to_a
      end

      COLOR_WORDS = { "white" => "W", "blue" => "U", "black" => "B", "red" => "R", "green" => "G" }.freeze

      # The token cards the given cards can make. Scryfall's all_parts names each token
      # (and points at a printing we don't keep), but many tokens share a name — a
      # "Goblin" can be 1/1 red or 2/2 black — so among same-named tokens we pick the
      # one whose size and colors match what the card's text says it creates
      # ("create a 1/1 red Goblin creature token").
      def deck_tokens(card_ids)
        sources = ::Card.where(id: card_ids.uniq).where.not(related_tokens: []).to_a
        tokens = ::Card.where(layout: TOKEN_LAYOUTS)
        sources.flat_map { |source|
          text = [ source.oracle_text, *Array(source.card_faces).map { |f| f["oracle_text"] } ].compact.join("\n")
          source.related_tokens.filter_map do |part|
            candidates = tokens.where(name: part["name"], type_line: part["type_line"]).to_a.presence ||
                         tokens.where(name: part["name"]).to_a
            candidates.max_by { |token| token_match_score(token, text) }
          end
        }.uniq(&:id).sort_by(&:name)
      end

      def legal?(card:, format:)
        card.legal_in?(format)
      end

      private

      def token_match_score(token, text)
        return 0 unless token.power && token.toughness

        phrase = text.match(/#{Regexp.escape(token.power)}\/#{Regexp.escape(token.toughness)} ([a-z ,]*?)#{Regexp.escape(token.name)}/i)
        return 0 unless phrase

        said = COLOR_WORDS.filter_map { |word, color| color if phrase[1].downcase.include?(word) }
        said.sort == Array(token.colors).sort ? 2 : 1
      end

      def upsert_bulk(card_attrs_list)
        # record_timestamps: false — the importer already sets created_at/updated_at
        # itself; leaving Rails' own timestamp touching on double-assigns `updated_at`
        # in the generated ON CONFLICT DO UPDATE SET clause (PG::SyntaxError).
        ::Card.upsert_all(
          card_attrs_list,
          unique_by: :index_cards_on_scryfall_oracle_id,
          record_timestamps: false,
          update_only: %i[
            name name_normalized front_face_name_normalized mana_cost cmc type_line oracle_text power toughness loyalty related_tokens colors color_identity
            legalities image_uris card_faces alternate_names_normalized layout set_code collector_number rarity updated_at
          ]
        )
      end
    end
  end
end
