module Table
  module Actions
    class ChangeManaPool < Shared::BaseAction
      def call(...) = Interactions::ApplyManaPool.call(...)
    end
  end
end
