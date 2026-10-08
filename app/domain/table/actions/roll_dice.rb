module Table
  module Actions
    class RollDice < Shared::BaseAction
      def call(...) = Interactions::ApplyDiceRoll.call(...)
    end
  end
end
