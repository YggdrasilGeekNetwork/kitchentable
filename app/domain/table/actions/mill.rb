module Table
  module Actions
    class Mill < Shared::BaseAction
      def call(...) = Interactions::ApplyMill.call(...)
    end
  end
end
