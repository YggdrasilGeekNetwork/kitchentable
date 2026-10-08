module Table
  module Actions
    class SetLife < Shared::BaseAction
      def call(...) = Interactions::ApplyLifeChange.call(...)
    end
  end
end
