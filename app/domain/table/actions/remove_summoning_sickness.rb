module Table
  module Actions
    class RemoveSummoningSickness < Shared::BaseAction
      def call(...) = Interactions::ApplyRemoveSickness.call(...)
    end
  end
end
