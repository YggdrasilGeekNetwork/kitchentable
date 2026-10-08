module Table
  module Entities
    # Result of validating a submitted decklist against a format's rules. Never
    # persisted — consumed immediately by Table::Interactions::StartGame to populate
    # a seat's library/command zone in the ephemeral GameState.
    class ValidatedDeck
      attr_reader :format, :library_card_ids, :command_card_ids, :errors

      def initialize(format:, library_card_ids: [], command_card_ids: [], errors: [])
        @format = format
        @library_card_ids = library_card_ids
        @command_card_ids = command_card_ids
        @errors = errors
      end

      def valid? = errors.empty?
    end
  end
end
