module Table
  module Actions
    class AdjustCardCounter < Shared::BaseAction
      def call(...) = Interactions::ApplyCardCounter.call(...)
    end
  end
end
