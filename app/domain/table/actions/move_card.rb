module Table
  module Actions
    class MoveCard < Shared::BaseAction
      def call(...) = Interactions::ApplyCardMove.call(...)
    end
  end
end
