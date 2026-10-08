module Table
  module Actions
    class MoveCards < Shared::BaseAction
      def call(...) = Interactions::ApplyCardMoves.call(...)
    end
  end
end
