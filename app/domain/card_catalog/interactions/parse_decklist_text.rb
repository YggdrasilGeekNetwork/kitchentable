module CardCatalog
  module Interactions
    # Pure text -> structured entries. Never resolves card names against the catalog
    # and never validates legality — that's Table::Interactions::ValidateDecklist's job.
    # Accepts a plain list ("4 Lightning Bolt"), the MTGA/MTGO export suffix
    # ("4 Lightning Bolt (LEA) 161"), and section headers (Deck/Sideboard/Companion).
    # The commander is chosen in a separate field, so a "Commander" header from an
    # export just keeps its cards in the main list.
    class ParseDecklistText < Shared::BaseInteraction
      Entry = Struct.new(:section, :quantity, :raw_name, :raw_line, :line_number, keyword_init: true)

      SECTION_HEADERS = {
        "deck" => :main, "mainboard" => :main,
        "commander" => :main,
        "sideboard" => :sideboard, "companion" => :sideboard
      }.freeze

      LINE_PATTERN = /\A(?<qty>\d+)\s+(?<name>.+?)(?:\s+\([A-Za-z0-9]{2,5}\)\s*[A-Za-z0-9-]*)?\z/

      def call(text:)
        entries = []
        warnings = []
        section = :main

        text.to_s.each_line.with_index(1) do |raw_line, line_number|
          line = raw_line.strip
          next if line.empty? || line.start_with?("//", "#")

          header_key = line.delete_suffix(":").downcase
          if SECTION_HEADERS.key?(header_key)
            section = SECTION_HEADERS[header_key]
            next
          end

          match = LINE_PATTERN.match(line)
          if match
            entries << Entry.new(
              section: section, quantity: match[:qty].to_i, raw_name: match[:name].strip,
              raw_line: line, line_number: line_number
            )
          else
            warnings << { line_number: line_number, raw_line: line, message: "Line ignored (unparseable)" }
          end
        end

        Success(entries: entries, warnings: warnings)
      end
    end
  end
end
