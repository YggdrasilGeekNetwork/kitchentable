module Table
  module Actions
    class SendChatMessage < Shared::BaseAction
      def call(...) = Interactions::ApplyChatMessage.call(...)
    end
  end
end
