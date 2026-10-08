module Table
  module Views
    # What one player (the viewer) is allowed to see of a table's GameState. This is
    # the single place hidden information is redacted — every broadcast and the
    # initial snapshot go through it, so the board UI can never receive more than it
    # should show:
    #   - battlefield/graveyard/exile/command zones are public, except a face-down
    #     card's identity, which only its controller sees
    #   - a hand's cards are visible only to its owner (others get a count)
    #   - libraries are never listed, except the cards the viewer revealed to
    #     themselves from one (still there), and the top card of a library its owner
    #     plays with revealed (visible to everyone)
    #   - cards in an active reveal are visible to everyone
    #   - commanders are public knowledge wherever they are, so commander damage can
    #     always be tracked against them
    class TableView
      LOG_SIZE = 80

      def initialize(state:, seats:, viewer_seat_id:)
        @state = state
        @seats = seats
        @viewer = viewer_seat_id.to_s
        @card_ids = Set.new
      end

      # Card ids this viewer may see — the caller resolves them to catalog data.
      attr_reader :card_ids

      def to_h
        @to_h ||= {
          "type" => "table_view",
          "viewer_seat_id" => @viewer,
          "turn_number" => @state.turn_number,
          "active_seat_id" => @state.active_seat_id,
          "turn_started" => @state.turn_started,
          "round" => @state.round,
          "first_seat_id" => @state.first_seat_id,
          "awaiting_first_turn" => @state.awaiting_first_turn?,
          "seats" => @seats.sort_by(&:seat_number).map { |seat| seat_view(seat) },
          "reveals" => reveal_views,
          "commanders" => commander_views,
          "restart_vote" => restart_vote_view,
          "log" => log_view
        }
      end

      private

      def seat_view(seat)
        seat_id = seat.id.to_s
        seat_state = @state.seat(seat_id)
        base = { "seat_id" => seat_id, "display_name" => seat.display_name, "seat_number" => seat.seat_number,
                 "ready" => !seat_state.nil? }
        return base unless seat_state

        base.merge(
          "life_total" => seat_state.life_total,
          "mulligan_count" => seat_state.mulligan_count,
          "hand_kept" => seat_state.hand_kept,
          "turns_taken" => seat_state.turns_taken,
          "commander_damage" => seat_state.commander_damage,
          "mana_pool" => seat_state.mana_pool,
          "counters" => seat_state.counters,
          "peek" => seat_state.peek,
          "zone_counts" => seat_state.zones.transform_values(&:size),
          "zones" => zones_view(seat_id, seat_state),
          "library_top" => library_top_view(seat_id, seat_state),
          "top_revealed" => seat_state.top_revealed,
          "library_top_card" => library_top_card_view(seat_id, seat_state)
        )
      end

      def zones_view(seat_id, seat_state)
        visible = Entities::SeatState::PUBLIC_ZONES + (seat_id == @viewer ? [ "hand" ] : [])
        visible.index_with { |zone| seat_state.zones[zone].map { |id| instance_view(id, seat_state.instances[id], seat_id) } }
      end

      def library_top_view(seat_id, seat_state)
        peek = @state.seat(@viewer)&.peek
        return nil unless peek && peek["seat_id"].to_s == seat_id

        library = seat_state.zones["library"]
        (peek["card_instance_ids"].to_a & library).map { |id| instance_view(id, seat_state.instances[id], seat_id, force_visible: true) }
      end

      def library_top_card_view(seat_id, seat_state)
        top = seat_state.zones["library"].first
        return nil unless seat_state.top_revealed && top

        instance_view(top, seat_state.instances[top], seat_id, force_visible: true)
      end

      def reveal_views
        @state.reveals.filter_map do |reveal|
          cards = reveal["card_instance_ids"].filter_map do |id|
            holder_id, _zone = @state.locate(id)
            instance_view(id, @state.seat(holder_id).instances[id], holder_id, force_visible: true) if holder_id
          end
          reveal.slice("id", "by_seat_id", "owner_seat_id").merge("cards" => cards) if cards.any?
        end
      end

      # Everyone dealt in has to accept; `pending` is who hasn't yet.
      def restart_vote_view
        vote = @state.restart_vote
        return nil unless vote

        vote.merge("pending" => @state.seats.keys - vote["accepted"])
      end

      def commander_views
        @state.seats.flat_map do |_seat_id, seat_state|
          seat_state.instances.filter_map do |id, instance|
            next unless instance.commander

            @card_ids << instance.card_id
            { "instance_id" => id, "owner_seat_id" => instance.owner_seat_id, "card_id" => instance.card_id }
          end
        end
      end

      def log_view
        @state.log.last(LOG_SIZE).map do |event|
          @card_ids << event.payload["card_id"] if event.payload["card_id"]
          event.to_h
        end
      end

      def instance_view(id, instance, controller_seat_id, force_visible: false)
        hidden = instance.face_down && controller_seat_id.to_s != @viewer && !force_visible
        @card_ids << instance.card_id unless hidden

        instance.to_h.except("card_id", "custom").merge(
          "id" => id, "card_id" => hidden ? nil : instance.card_id, "custom" => hidden ? nil : instance.custom,
          "controller_seat_id" => controller_seat_id.to_s
        )
      end
    end
  end
end
