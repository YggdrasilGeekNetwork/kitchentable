module Table
  module Actions
    class StartTurn < Shared::BaseAction
      def call(...) = Interactions::ApplyStartTurn.call(...)
    end
  end
end
