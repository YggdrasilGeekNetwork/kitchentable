module Table
  module Actions
    class NewTurn < Shared::BaseAction
      def call(...) = Interactions::ApplyNewTurn.call(...)
    end
  end
end
