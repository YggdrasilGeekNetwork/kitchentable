module Table
  module Actions
    class VoteRestart < Shared::BaseAction
      def call(...) = Interactions::ApplyRestartVote.call(...)
    end
  end
end
