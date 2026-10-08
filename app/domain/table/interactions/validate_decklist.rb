module Table
  module Interactions
    class ValidateDecklist < Shared::BaseInteraction
      FORMAT_RULES = {
        "commander" => DeckValidators::CommanderRules,
        "standard" => DeckValidators::StandardRules
      }.freeze

      def initialize(
        catalog: Persistence::Postgres::CardCatalogRepository.new,
        parser: CardCatalog::Interactions::ParseDecklistText
      )
        @catalog = catalog
        @parser = parser
      end

      def call(raw_text:, format:, commander_names: [])
        rules_class = FORMAT_RULES[format.to_s]
        unless rules_class
          return Failure[:validation_error, [ { type: "unknown_format", message: "Unsupported format: #{format}" } ]]
        end

        parsed = step @parser.call(text: raw_text)
        commander_entries = step commander_entries(commander_names, format.to_s)
        resolved = step resolve_cards(commander_entries + parsed[:entries])
        step rules_class.new(catalog: @catalog).call(without_commanders_in_list(resolved))
      end

      private

      # Commanders (one, or two for Partner/Background pairs) are chosen in their own
      # fields, never by a section of the list.
      def commander_entries(commander_names, format)
        return Success([]) unless format == "commander"

        names = Array(commander_names).map { |n| n.to_s.strip }.reject(&:empty?)
        if names.empty?
          return Failure[:validation_error, [ { type: "commander_missing", message: "Choose your commander" } ]]
        end

        Success(names.map { |name|
          CardCatalog::Interactions::ParseDecklistText::Entry.new(
            section: :commander, quantity: 1, raw_name: name, raw_line: name, line_number: nil
          )
        })
      end

      # Exports usually include the commanders in the 100-card list too; drop one copy
      # of each from the list so they aren't counted (or dealt) twice.
      def without_commanders_in_list(resolved)
        commanders = resolved.select { |r| r[:entry].section == :commander }
        commanders.reduce(resolved) { |rows, commander| without_one_copy(rows, commander[:card]) }
      end

      def without_one_copy(rows, card)
        duplicate = rows.find { |r| r[:entry].section == :main && r[:card].id == card.id }
        return rows unless duplicate

        remaining = duplicate[:entry].quantity - 1
        rest = rows.reject { |r| r.equal?(duplicate) }
        return rest if remaining.zero?

        rest + [ { entry: duplicate[:entry].dup.tap { |e| e.quantity = remaining }, card: duplicate[:card] } ]
      end

      def resolve_cards(entries)
        errors = []

        resolved = entries.filter_map do |entry|
          card = @catalog.find_by_name(entry.raw_name)
          if card
            { entry: entry, card: card }
          else
            errors << { type: "unresolved_card", raw_name: entry.raw_name, line_number: entry.line_number,
                        message: "Unknown card: \"#{entry.raw_name}\"" }
            nil
          end
        end

        errors.any? ? Failure[:validation_error, errors] : Success(resolved)
      end
    end
  end
end
