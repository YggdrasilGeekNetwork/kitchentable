module Table
  module Actions
    class PlaceRevealedRest < Shared::BaseAction
      def call(...) = Interactions::ApplyPeekRemaining.call(...)
    end
  end
end
