module Table
  module Entities
    # One copy of a card in play. Immutable value object — mutations return a new
    # instance (with / with_*), matching the rest of the ephemeral game-state entities.
    #
    # `owner_seat_id` never changes: a card whose control moved to another seat's
    # battlefield still goes back to its owner's hand/graveyard/library/exile.
    # `x`/`y` are battlefield coordinates as percentages of the controller's play area.
    # `face_index` picks which face of a multi-face card is up (0 = front).
    # `power_mod`/`toughness_mod` are "until end of turn"-style adjustments players
    # apply by hand. `custom` describes a card made up at the table (no catalog card):
    # { "name", "type_line", "power", "toughness" }. `commander` marks the cards dealt
    # into the command zone — they stay commanders wherever they go. `sick` marks a
    # creature with summoning sickness (it came under its controller's control this
    # turn).
    class CardInstance
      ATTRIBUTES = %i[card_id owner_seat_id tapped face_down face_index counters x y token power_mod toughness_mod custom
                      commander sick].freeze

      attr_reader(*ATTRIBUTES)

      def initialize(card_id:, owner_seat_id: nil, tapped: false, face_down: false, face_index: 0,
                     counters: {}, x: nil, y: nil, token: false, power_mod: 0, toughness_mod: 0, custom: nil, commander: false, sick: false)
        @card_id = card_id
        @owner_seat_id = owner_seat_id&.to_s
        @tapped = tapped
        @face_down = face_down
        @face_index = face_index
        @counters = counters
        @x = x
        @y = y
        @token = token
        @power_mod = power_mod
        @toughness_mod = toughness_mod
        @custom = custom
        @commander = commander
        @sick = sick
      end

      def with(**changes)
        self.class.new(**ATTRIBUTES.index_with { |attr| public_send(attr) }.merge(changes))
      end

      def with_tapped(value) = with(tapped: value)

      # Counters that drop to zero disappear rather than lingering as "0".
      def with_counter(key, delta)
        value = counters.fetch(key.to_s, 0) + delta
        with(counters: value.zero? ? counters.except(key.to_s) : counters.merge(key.to_s => value))
      end

      # What a card keeps when it leaves the battlefield: only its identity.
      def leaving_battlefield
        with(tapped: false, face_down: false, face_index: 0, counters: {}, x: nil, y: nil, power_mod: 0, toughness_mod: 0, sick: false)
      end

      def to_h
        {
          "card_id" => card_id, "owner_seat_id" => owner_seat_id, "tapped" => tapped,
          "face_down" => face_down, "face_index" => face_index, "counters" => counters,
          "x" => x, "y" => y, "token" => token,
          "power_mod" => power_mod, "toughness_mod" => toughness_mod, "custom" => custom, "commander" => commander,
          "sick" => sick
        }
      end

      def self.from_h(hash)
        new(
          card_id: hash["card_id"],
          owner_seat_id: hash["owner_seat_id"],
          tapped: hash["tapped"] || false,
          face_down: hash["face_down"] || false,
          face_index: hash["face_index"] || 0,
          counters: hash["counters"] || {},
          x: hash["x"],
          y: hash["y"],
          token: hash["token"] || false,
          power_mod: hash["power_mod"] || 0,
          toughness_mod: hash["toughness_mod"] || 0,
          custom: hash["custom"],
          commander: hash["commander"] || false,
          sick: hash["sick"] || false
        )
      end
    end
  end
end
