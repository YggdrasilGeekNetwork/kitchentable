module Table
  module Entities
    # Live state for one seat: life total, the six zones (each an ordered array of
    # card_instance ids — library index 0 is the top), the instances themselves keyed
    # by id, player counters (poison, energy, commander damage...), and `peek`: the
    # cards this player revealed to themselves from a library (own or another seat's),
    # as { "seat_id", "card_instance_ids", "search" } — a fixed set: cards leave it as
    # they're moved, nothing new slides in. `top_revealed`: playing with the library's
    # top card revealed to everyone. `turns_taken` counts the turns this player has
    # started. `hand_kept` is false while
    # the player is still deciding on their opening hand (keep or mulligan).
    # `commander_damage` is the damage this player has taken from each commander, keyed
    # by the commander's card instance id. `deck` is the decklist the seat was dealt
    # ({ "format", "library" => [card_id...], "command" => [card_id...] }), kept so the
    # game can be restarted without resubmitting. `mana_pool` is a manual tracker of the
    # mana the player has floating ({ "W" => 2, "G" => 1 }).
    class SeatState
      # `stack` holds the player's spells being cast until they resolve to the
      # graveyard or exile — public, like on a real table.
      ZONES = %w[library hand battlefield stack graveyard exile command].freeze
      PUBLIC_ZONES = %w[battlefield stack graveyard exile command].freeze
      DEFAULT_LIFE_TOTAL = 20
      ATTRIBUTES = %i[life_total zones instances mulligan_count counters peek hand_kept commander_damage deck mana_pool top_revealed turns_taken].freeze
      OPENING_HAND_SIZE = 7
      STARTING_LIFE = { "commander" => 40 }.freeze

      attr_reader(*ATTRIBUTES)

      def initialize(life_total: DEFAULT_LIFE_TOTAL, zones: nil, instances: {}, mulligan_count: 0, counters: {}, peek: nil,
                     hand_kept: true, commander_damage: {}, deck: nil, mana_pool: {},
                     top_revealed: false, turns_taken: 0)
        @life_total = life_total
        @zones = ZONES.index_with { [] }.merge((zones || {}).slice(*ZONES))
        @instances = instances
        @mulligan_count = mulligan_count
        @counters = counters
        @peek = peek
        @hand_kept = hand_kept
        @commander_damage = commander_damage
        @deck = deck
        @mana_pool = mana_pool
        @top_revealed = top_revealed
        @turns_taken = turns_taken
      end

      # A freshly dealt seat: shuffled library, 7-card opening hand still to be kept,
      # commanders in the command zone, the format's starting life.
      def self.deal(seat_id:, deck:)
        instances = {}
        register = lambda do |card_id, commander|
          id = SecureRandom.hex(6)
          instances[id] = CardInstance.new(card_id: card_id, owner_seat_id: seat_id.to_s, commander: commander)
          id
        end
        library = deck["library"].shuffle.map { |card_id| register.call(card_id, false) }
        command = deck["command"].map { |card_id| register.call(card_id, true) }

        new(
          life_total: STARTING_LIFE.fetch(deck["format"], DEFAULT_LIFE_TOTAL),
          instances: instances,
          zones: { "library" => library.drop(OPENING_HAND_SIZE), "hand" => library.first(OPENING_HAND_SIZE), "command" => command },
          hand_kept: false,
          deck: deck
        )
      end

      def with(**changes)
        self.class.new(**ATTRIBUTES.index_with { |attr| public_send(attr) }.merge(changes))
      end

      def with_life_total(value) = with(life_total: value)
      def with_zones(new_zones) = with(zones: new_zones)
      def with_instances(new_instances) = with(instances: new_instances)
      def with_mulligan_count(value) = with(mulligan_count: value)

      def with_instance(instance_id, instance) = with(instances: instances.merge(instance_id => instance))

      def zone_of(instance_id)
        zones.find { |_zone, ids| ids.include?(instance_id) }&.first
      end

      def without_card(instance_id)
        with(zones: zones.transform_values { |ids| ids - [ instance_id ] }, instances: instances.except(instance_id))
      end

      # `position` is clamped; a negative position counts from the end (-1 = bottom).
      def with_card(instance_id, instance, zone:, position: nil)
        ids = zones.fetch(zone).dup
        index = position.nil? ? ids.size : position
        index = ids.size + 1 + index if index.negative?
        ids.insert(index.clamp(0, ids.size), instance_id)
        with(zones: zones.merge(zone => ids), instances: instances.merge(instance_id => instance))
      end

      # Player counters stay on screen once added, even at zero, until removed; they
      # never go negative.
      def with_counter(key, delta)
        with(counters: counters.merge(key.to_s => [ counters.fetch(key.to_s, 0) + delta, 0 ].max))
      end

      def without_counter(key) = with(counters: counters.except(key.to_s))

      def to_h
        {
          "life_total" => life_total,
          "zones" => zones,
          "instances" => instances.transform_values(&:to_h),
          "mulligan_count" => mulligan_count,
          "counters" => counters,
          "peek" => peek,
          "hand_kept" => hand_kept,
          "commander_damage" => commander_damage,
          "deck" => deck,
          "mana_pool" => mana_pool,
          "top_revealed" => top_revealed,
          "turns_taken" => turns_taken
        }
      end

      def self.from_h(hash)
        hash ||= {}
        instances = (hash["instances"] || {}).transform_values { |i| CardInstance.from_h(i) }
        new(
          life_total: hash["life_total"] || DEFAULT_LIFE_TOTAL,
          zones: hash["zones"],
          instances: instances,
          mulligan_count: hash["mulligan_count"] || 0,
          counters: hash["counters"] || {},
          peek: hash["peek"],
          hand_kept: hash.fetch("hand_kept", true),
          commander_damage: hash["commander_damage"] || {},
          deck: hash["deck"],
          mana_pool: hash["mana_pool"] || {},
          top_revealed: hash["top_revealed"] || false,
          turns_taken: hash["turns_taken"] || 0
        )
      end
    end
  end
end
