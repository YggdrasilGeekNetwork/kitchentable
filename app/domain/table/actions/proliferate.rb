module Table
  module Actions
    class Proliferate < Shared::BaseAction
      def call(...) = Interactions::ApplyProliferate.call(...)
    end
  end
end
