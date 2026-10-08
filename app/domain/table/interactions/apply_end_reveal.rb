module Table
  module Interactions
    # Ends a reveal. Only the player who made it can end it for everyone.
    class ApplyEndReveal < BaseGameMutation
      def call(table_slug:, seat_id:, reveal_id:)
        step apply(table_slug) { |state| end_reveal(state, seat_id.to_s, reveal_id.to_s) }
      end

      private

      def end_reveal(state, actor_id, reveal_id)
        reveal = state.reveals.find { |r| r["id"] == reveal_id }
        return Failure[:not_found, "Reveal not found"] unless reveal
        return Failure[:forbidden, "Only whoever revealed can end the reveal"] unless reveal["by_seat_id"] == actor_id

        Success(state.with(reveals: state.reveals - [ reveal ]))
      end
    end
  end
end
