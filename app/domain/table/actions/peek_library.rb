module Table
  module Actions
    class PeekLibrary < Shared::BaseAction
      def call(...) = Interactions::ApplyPeek.call(...)
    end
  end
end
