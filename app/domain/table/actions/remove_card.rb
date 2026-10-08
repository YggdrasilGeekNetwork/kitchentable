module Table
  module Actions
    class RemoveCard < Shared::BaseAction
      def call(...) = Interactions::ApplyRemoveCard.call(...)
    end
  end
end
