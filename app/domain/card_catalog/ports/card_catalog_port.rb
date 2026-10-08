module CardCatalog
  module Ports
    # Durable reference data (Scryfall oracle cards) — low write frequency, safe to
    # keep as normalized Postgres rows (unlike in-game card instances).
    class CardCatalogPort
      def find_by_name(name)
        raise NotImplementedError
      end

      # { id => card } for the given ids; unknown ids are simply absent.
      def find_many(ids)
        raise NotImplementedError
      end

      # Playable cards and tokens whose name starts with (then contains) `query`.
      def search(query, limit: 12)
        raise NotImplementedError
      end

      # Token cards that any of the given cards can create.
      def deck_tokens(card_ids)
        raise NotImplementedError
      end

      def legal?(card:, format:)
        raise NotImplementedError
      end

      def upsert_bulk(card_attrs_list)
        raise NotImplementedError
      end
    end
  end
end
