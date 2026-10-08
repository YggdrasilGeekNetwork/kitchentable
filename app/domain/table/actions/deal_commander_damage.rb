module Table
  module Actions
    class DealCommanderDamage < Shared::BaseAction
      def call(...) = Interactions::ApplyCommanderDamage.call(...)
    end
  end
end
