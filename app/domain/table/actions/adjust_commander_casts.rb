module Table
  module Actions
    class AdjustCommanderCasts < Shared::BaseAction
      def call(...) = Interactions::ApplyCommanderCasts.call(...)
    end
  end
end
