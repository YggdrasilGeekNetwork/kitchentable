module Table
  module Entities
    # The whole ephemeral state for one table: every seat's life/zones/instances, whose
    # turn it is, cards currently revealed to everyone, and a capped recent-event log.
    # Serialized as a single JSON blob by Persistence::Redis::GameStateStore — never
    # stored as Postgres rows.
    #
    # `reveals` entries: { "id", "by_seat_id", "owner_seat_id", "card_instance_ids" }.
    # `restart_vote`, while someone asked to restart: { "id", "requested_by",
    # "accepted" => [seat_id...] }. `turn_started` is whether the active player has
    # begun their turn (untapped and drawn) yet. `round` counts full rotations around
    # the table: it goes up when the turn passes back to `first_seat_id`, the player
    # who opened the game. `turn_number` is the total number of turns played.
    class GameState
      LOG_CAP = 200
      ATTRIBUTES = %i[turn_number round first_seat_id active_seat_id turn_started seats reveals restart_vote log].freeze

      attr_reader(*ATTRIBUTES)

      def initialize(turn_number: 1, round: 1, first_seat_id: nil, active_seat_id: nil, turn_started: false, seats: {}, reveals: [],
                     restart_vote: nil, log: [])
        @turn_number = turn_number
        @round = round
        @first_seat_id = first_seat_id&.to_s
        @active_seat_id = active_seat_id&.to_s
        @turn_started = turn_started
        @seats = seats
        @reveals = reveals
        @restart_vote = restart_vote
        @log = log
      end

      def with(**changes)
        self.class.new(**ATTRIBUTES.index_with { |attr| public_send(attr) }.merge(changes))
      end

      def seat(seat_id) = seats[seat_id.to_s]

      # Nobody has played yet: the first player hasn't started turn 1.
      def awaiting_first_turn? = turn_number == 1 && !turn_started

      def with_seat(seat_id, seat_state) = with(seats: seats.merge(seat_id.to_s => seat_state))
      def with_turn_number(value) = with(turn_number: value)

      # [seat_id, zone] currently holding the instance, across every seat.
      def locate(instance_id)
        seats.each do |seat_id, seat_state|
          zone = seat_state.zone_of(instance_id)
          return [ seat_id, zone ] if zone
        end
        nil
      end

      # A card that was moved stops being part of anyone's peek; a peek with nothing
      # left ends.
      def without_peeked(instance_id)
        seats.reduce(self) do |state, (seat_id, seat_state)|
          ids = seat_state.peek&.dig("card_instance_ids")
          next state unless ids&.include?(instance_id)

          rest = ids - [ instance_id ]
          state.with_seat(seat_id, seat_state.with(peek: rest.empty? ? nil : seat_state.peek.merge("card_instance_ids" => rest)))
        end
      end

      # Peeks into a library that was shuffled are over: those cards aren't on top now.
      def without_peeks_into(library_seat_id)
        seats.reduce(self) do |state, (seat_id, seat_state)|
          next state unless seat_state.peek && seat_state.peek["seat_id"].to_s == library_seat_id.to_s

          state.with_seat(seat_id, seat_state.with(peek: nil))
        end
      end

      def next_sequence
        (log.map(&:sequence).max || 0) + 1
      end

      def with_log_event(event)
        with(log: (log + [ event ]).last(LOG_CAP))
      end

      def to_h
        {
          "turn_number" => turn_number,
          "round" => round,
          "first_seat_id" => first_seat_id,
          "active_seat_id" => active_seat_id,
          "turn_started" => turn_started,
          "seats" => seats.transform_values(&:to_h),
          "reveals" => reveals,
          "restart_vote" => restart_vote,
          "log" => log.map(&:to_h)
        }
      end

      def self.from_h(hash)
        hash ||= {}
        seats = (hash["seats"] || {}).transform_values { |s| SeatState.from_h(s) }
        log = (hash["log"] || []).map { |e| LogEvent.from_h(e) }
        new(
          turn_number: hash["turn_number"] || 1,
          round: hash["round"] || 1,
          first_seat_id: hash["first_seat_id"],
          active_seat_id: hash["active_seat_id"],
          turn_started: hash["turn_started"] || false,
          seats: seats,
          reveals: hash["reveals"] || [],
          restart_vote: hash["restart_vote"],
          log: log
        )
      end

      def self.blank
        new
      end
    end
  end
end
