module Table
  module Interactions
    # Restarting the game is a vote: one player asks, every player dealt in must accept,
    # and any refusal (or the requester changing their mind) cancels it. Once everyone
    # has accepted, every seat is dealt a fresh game from the deck it was last dealt,
    # and the first player is drawn at random.
    #
    #   request: seat asks (counts as their own acceptance)
    #   accept / decline: answer the pending vote
    class ApplyRestartVote < BaseGameMutation
      ANSWERS = %w[request accept decline].freeze

      def initialize(rng: Random.new, **deps)
        super(**deps)
        @rng = rng
      end

      def call(table_slug:, seat_id:, answer:)
        answer = answer.to_s
        return Failure[:validation_error, "Unknown answer: #{answer}"] unless ANSWERS.include?(answer)

        @format = table_repo.find_by_slug(table_slug)&.format
        step apply(table_slug) { |state| vote(state, seat_id.to_s, answer) }
      end

      private

      def vote(state, seat_id, answer)
        return Failure[:forbidden, "Only players in the game can vote"] unless state.seat(seat_id)

        vote = state.restart_vote
        case answer
        when "request"
          return Failure[:validation_error, "A restart was already requested"] if vote

          vote = { "id" => SecureRandom.hex(4), "requested_by" => seat_id, "accepted" => [ seat_id ] }
          tally(append_log(state, seat_id: seat_id, event_type: "restart_requested"), vote)
        when "accept"
          return Failure[:not_found, "No restart was requested"] unless vote

          tally(state, vote.merge("accepted" => (vote["accepted"] | [ seat_id ])))
        when "decline"
          return Failure[:not_found, "No restart was requested"] unless vote

          Success(append_log(state.with(restart_vote: nil), seat_id: seat_id, event_type: "restart_declined"))
        end
      end

      def tally(state, vote)
        everyone_accepted = (state.seats.keys - vote["accepted"]).empty?
        everyone_accepted ? Success(restart(state)) : Success(state.with(restart_vote: vote))
      end

      def restart(state)
        seats = state.seats.to_h do |seat_id, seat_state|
          [ seat_id, Entities::SeatState.deal(seat_id: seat_id, deck: seat_state.deck || rebuilt_deck(state, seat_id)) ]
        end
        first = seats.keys.sample(random: @rng)

        fresh = Entities::GameState.new(turn_number: 1, round: 1, first_seat_id: first, active_seat_id: first, seats: seats)
        append_log(fresh, seat_id: first, event_type: "restart", payload: { "first_seat_id" => first })
      end

      # Seats dealt before decks were remembered: their deck is every catalog card they
      # own, wherever it is now (tokens and custom cards aren't part of a deck).
      # Commanders are the cards marked as such, or — in games older than that mark —
      # whatever is in their command zone.
      def rebuilt_deck(state, seat_id)
        owned = state.seats.flat_map do |holder_id, seat_state|
          seat_state.instances.filter_map do |id, instance|
            owner = instance.owner_seat_id || holder_id
            next if owner != seat_id || instance.token || instance.card_id.nil?

            [ instance, holder_id == seat_id && seat_state.zone_of(id) == "command" ]
          end
        end
        flagged = owned.any? { |instance, _| instance.commander }
        commanders, library = owned.partition { |instance, in_command| flagged ? instance.commander : in_command }

        { "format" => @format, "library" => library.map { |i, _| i.card_id }, "command" => commanders.map { |i, _| i.card_id } }
      end
    end
  end
end
