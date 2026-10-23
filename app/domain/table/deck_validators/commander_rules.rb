module Table
  module DeckValidators
    class CommanderRules < Shared::BaseInteraction
      DECK_SIZE = 100
      # A second commander covers Partner, Friends forever, Doctor's companion and
      # "Choose a Background" pairs. Whether the two cards may actually pair up is
      # left to the players, like every other rule.
      MAX_COMMANDERS = 2

      def initialize(catalog:)
        @catalog = catalog
      end

      # `ignore_deck_size`: the player was warned about the card count and chose to
      # play anyway (a deck mid-build, a casual variant...).
      def call(resolved, ignore_deck_size: false)
        commander_rows, deck_rows = resolved.partition { |r| r[:entry].section == :commander }
        errors = []

        unless commander_rows.size.between?(1, MAX_COMMANDERS)
          errors << { type: "commander_count",
                      message: "Decks de Commander precisam de 1 ou #{MAX_COMMANDERS} comandantes (encontrados: #{commander_rows.size})" }
        end

        total = resolved.sum { |r| r[:entry].quantity }
        unless total == DECK_SIZE || ignore_deck_size
          errors << { type: "deck_size", message: "Decks de Commander precisam ter exatamente #{DECK_SIZE} cartas, contando o comandante (encontradas: #{total})" }
        end

        errors.concat(singleton_violations(resolved))
        errors.concat(color_identity_violations(deck_rows, commander_rows)) if commander_rows.any?
        errors.concat(legality_violations(resolved))

        return Failure[:validation_error, errors] if errors.any?

        Success(
          Entities::ValidatedDeck.new(
            format: "commander",
            library_card_ids: deck_rows.flat_map { |r| [ r[:card].id ] * r[:entry].quantity },
            command_card_ids: commander_rows.map { |r| r[:card].id }
          )
        )
      end

      private

      def singleton_violations(resolved)
        resolved
          .reject { |r| r[:card].type_line.to_s.include?("Basic Land") }
          .group_by { |r| r[:card].id }
          .select { |_id, rows| rows.sum { |r| r[:entry].quantity } > 1 }
          .map { |_id, rows|
            { type: "singleton", card_name: rows.first[:card].name,
              message: "Só 1 cópia de #{rows.first[:card].name} é permitida em Commander" }
          }
      end

      # With two commanders, the deck's identity is the union of both.
      def color_identity_violations(deck_rows, commander_rows)
        commander_identity = commander_rows.flat_map { |r| r[:card].color_identity }.uniq
        deck_rows.filter_map do |r|
          card_identity = r[:card].color_identity
          next if (card_identity - commander_identity).empty?

          { type: "color_identity", card_name: r[:card].name,
            message: "#{r[:card].name} (#{card_identity.join}) está fora da identidade de cor do seu comandante (#{commander_identity.join})" }
        end
      end

      def legality_violations(resolved)
        resolved.filter_map do |r|
          next if @catalog.legal?(card: r[:card], format: "commander")

          { type: "legality", card_name: r[:card].name, message: "#{r[:card].name} é banida em Commander" }
        end
      end
    end
  end
end
