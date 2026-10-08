module Table
  module Actions
    class CreateCard < Shared::BaseAction
      def call(...) = Interactions::ApplyCreateCard.call(...)
    end
  end
end
