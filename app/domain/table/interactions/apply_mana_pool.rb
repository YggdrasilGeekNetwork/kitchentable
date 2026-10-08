module Table
  module Interactions
    # A manual mana pool tracker: players add and spend mana by hand (it isn't tied to
    # tapping lands). `delta` changes one color; `clear: true` empties the pool.
    class ApplyManaPool < BaseGameMutation
      COLORS = %w[W U B R G C].freeze

      def call(table_slug:, seat_id:, color: nil, delta: 0, clear: false)
        unless clear || COLORS.include?(color.to_s)
          return Failure[:validation_error, "Mana color must be one of #{COLORS.join(", ")}"]
        end

        step apply(table_slug) { |state| change(state, seat_id.to_s, color.to_s, delta.to_i, clear) }
      end

      private

      def change(state, seat_id, color, delta, clear)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state

        pool = clear ? {} : seat_state.mana_pool.merge(color => [ seat_state.mana_pool.fetch(color, 0) + delta, 0 ].max)
        Success(state.with_seat(seat_id, seat_state.with(mana_pool: pool.reject { |_, n| n.zero? })))
      end
    end
  end
end
