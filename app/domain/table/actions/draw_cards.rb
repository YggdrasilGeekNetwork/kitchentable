module Table
  module Actions
    class DrawCards < Shared::BaseAction
      def call(...) = Interactions::ApplyDraw.call(...)
    end
  end
end
