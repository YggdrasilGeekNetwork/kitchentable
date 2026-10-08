module Table
  module Interactions
    # Shared plumbing for every interaction that mutates a table's ephemeral GameState:
    #
    #   step apply(table_slug) { |state| ...return Success(new_state) or Failure... }
    #
    # locks the table's Postgres row (cheap mutex), fetches the Redis blob, runs the
    # block, saves the result, then — outside the lock, so a broadcast failure can't
    # roll back a state change — pushes every seat its own redacted TableView.
    #
    # The block must return a Result rather than use `step`: `step` exits by `throw`,
    # which must not unwind through the row-lock transaction.
    class BaseGameMutation < Shared::BaseInteraction
      def initialize(
        table_repo: Persistence::Postgres::TableRepository.new,
        state_store: Persistence::Redis::GameStateStore.new,
        broadcaster: Broadcasting::ActionCableBroadcaster.new,
        card_catalog: Persistence::Postgres::CardCatalogRepository.new
      )
        @table_repo = table_repo
        @state_store = state_store
        @broadcaster = broadcaster
        @card_catalog = card_catalog
      end

      private

      attr_reader :table_repo, :state_store, :broadcaster, :card_catalog

      def apply(table_slug)
        table = table_repo.find_by_slug(table_slug)
        return Failure[:not_found, "Table not found"] unless table

        result = table_repo.with_lock(table) do
          yield(state_store.fetch(table_slug: table_slug)).fmap do |new_state|
            state_store.save(table_slug: table_slug, state: new_state)
          end
        end

        if result.success?
          Views::ViewPublisher.new(card_catalog: card_catalog, broadcaster: broadcaster)
            .publish(table_slug: table_slug, state: result.value!, seats: table_repo.seats_for(table))
        end
        result
      end

      def find_seat_state(game_state, seat_id)
        seat_state = game_state.seat(seat_id)
        seat_state ? Success(seat_state) : Failure[:not_found, "Seat has no game state yet"]
      end

      def append_log(state, seat_id:, event_type:, payload: {})
        event = Entities::LogEvent.new(sequence: state.next_sequence, seat_id: seat_id.to_s, event_type: event_type, payload: payload)
        state.with_log_event(event)
      end

      # Players self-enforce the rules, but hidden information stays hidden: anyone
      # may handle cards in public zones (taking control, reanimating, exiling...),
      # while a hand or library card is only reachable by its holder, through an
      # active reveal, or within the top cards the actor is peeking at.
      def touchable?(state, actor_id, holder_id, zone, instance_id)
        return true if holder_id == actor_id.to_s
        return true if Entities::SeatState::PUBLIC_ZONES.include?(zone)
        return true if state.reveals.any? { |r| r["card_instance_ids"].include?(instance_id) }

        peek = state.seat(actor_id)&.peek
        zone == "library" && peek && peek["seat_id"].to_s == holder_id && peek["card_instance_ids"].to_a.include?(instance_id)
      end

      # Creatures get summoning sickness when they come under someone's control: by
      # front face type (a land // creature MDFC enters as a land).
      def creature?(instance)
        type_line = instance.custom ? instance.custom["type_line"] : card_catalog.find_many([ instance.card_id ])[instance.card_id]&.type_line
        type_line.to_s.split(" // ").first.to_s.include?("Creature")
      end

      # The start of a turn for a seat: untap everything, clear summoning sickness, draw
      # a card (if any are left). Returns the new seat state and how many were drawn.
      def begin_turn(seat_state)
        untapped = seat_state.zones["battlefield"].to_h { |id| [ id, seat_state.instances[id].with_tapped(false) ] }
        drawn = seat_state.zones["library"].first(1)
        new_seat_state = without_sickness(seat_state.with_instances(seat_state.instances.merge(untapped)))
                         .with_zones(seat_state.zones.merge("library" => seat_state.zones["library"].drop(1), "hand" => seat_state.zones["hand"] + drawn))
        [ new_seat_state, drawn.size ]
      end

      # Clears summoning sickness from everything a seat controls (its turn began).
      def without_sickness(seat_state)
        cured = seat_state.zones["battlefield"].to_h { |id| [ id, seat_state.instances[id].with(sick: false) ] }
        seat_state.with_instances(seat_state.instances.merge(cured))
      end

      # Logs name a card only when it was or becomes publicly visible.
      def public_card_id(instance, *zones)
        return nil if instance.face_down
        zones.any? { |z| Entities::SeatState::PUBLIC_ZONES.include?(z) } ? instance.card_id : nil
      end
    end
  end
end
