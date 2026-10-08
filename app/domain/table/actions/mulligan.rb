module Table
  module Actions
    class Mulligan < Shared::BaseAction
      def call(...) = Interactions::ApplyMulligan.call(...)
    end
  end
end
