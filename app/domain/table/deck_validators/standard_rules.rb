module Table
  module DeckValidators
    class StandardRules < Shared::BaseInteraction
      MIN_DECK_SIZE = 60
      MAX_COPIES = 4

      def initialize(catalog:)
        @catalog = catalog
      end

      def call(resolved)
        errors = []

        total = resolved.sum { |r| r[:entry].quantity }
        errors << { type: "deck_size", message: "Decks de Standard precisam de pelo menos #{MIN_DECK_SIZE} cartas (encontradas: #{total})" } if total < MIN_DECK_SIZE

        errors.concat(copy_limit_violations(resolved))
        errors.concat(legality_violations(resolved))

        return Failure[:validation_error, errors] if errors.any?

        Success(
          Entities::ValidatedDeck.new(
            format: "standard",
            library_card_ids: resolved.flat_map { |r| [ r[:card].id ] * r[:entry].quantity }
          )
        )
      end

      private

      def copy_limit_violations(resolved)
        resolved
          .reject { |r| r[:card].type_line.to_s.include?("Basic Land") }
          .group_by { |r| r[:card].id }
          .select { |_id, rows| rows.sum { |r| r[:entry].quantity } > MAX_COPIES }
          .map { |_id, rows|
            { type: "copy_limit", card_name: rows.first[:card].name,
              message: "No máximo #{MAX_COPIES} cópias de #{rows.first[:card].name}" }
          }
      end

      def legality_violations(resolved)
        resolved.filter_map do |r|
          next if @catalog.legal?(card: r[:card], format: "standard")

          { type: "legality", card_name: r[:card].name, message: "#{r[:card].name} não é legal em Standard" }
        end
      end
    end
  end
end
