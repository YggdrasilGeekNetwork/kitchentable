module Table
  module Actions
    class TapCard < Shared::BaseAction
      def call(...) = Interactions::ApplyTapCard.call(...)
    end
  end
end
