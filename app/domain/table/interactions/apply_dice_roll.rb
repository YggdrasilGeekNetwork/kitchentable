module Table
  module Interactions
    # Rolls an N-sided die (2 = coin flip) server-side, so everyone sees the same result.
    class ApplyDiceRoll < BaseGameMutation
      def initialize(rng: Random.new, **deps)
        super(**deps)
        @rng = rng
      end

      def call(table_slug:, seat_id:, sides:)
        sides = sides.to_i
        return Failure[:validation_error, "Dice need 2-1000 sides"] unless sides.between?(2, 1000)

        step apply(table_slug) { |state| roll(state, seat_id.to_s, sides) }
      end

      private

      def roll(state, seat_id, sides)
        Success(append_log(state, seat_id: seat_id, event_type: "dice_roll",
                           payload: { "sides" => sides, "result" => @rng.rand(1..sides) }))
      end
    end
  end
end
