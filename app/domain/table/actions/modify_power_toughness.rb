module Table
  module Actions
    class ModifyPowerToughness < Shared::BaseAction
      def call(...) = Interactions::ApplyPtModifier.call(...)
    end
  end
end
