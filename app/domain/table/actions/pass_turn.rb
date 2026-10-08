module Table
  module Actions
    class PassTurn < Shared::BaseAction
      def call(...) = Interactions::ApplyPassTurn.call(...)
    end
  end
end
