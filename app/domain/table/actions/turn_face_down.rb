module Table
  module Actions
    class TurnFaceDown < Shared::BaseAction
      def call(...) = Interactions::ApplyFaceDown.call(...)
    end
  end
end
