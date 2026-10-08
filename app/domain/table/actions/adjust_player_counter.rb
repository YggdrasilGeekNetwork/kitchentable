module Table
  module Actions
    class AdjustPlayerCounter < Shared::BaseAction
      def call(...) = Interactions::ApplyPlayerCounter.call(...)
    end
  end
end
