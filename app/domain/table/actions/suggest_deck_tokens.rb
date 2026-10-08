module Table
  module Actions
    class SuggestDeckTokens < Shared::BaseAction
      def call(...) = Interactions::FetchDeckTokens.call(...)
    end
  end
end
