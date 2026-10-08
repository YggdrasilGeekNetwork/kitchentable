module Table
  module Interactions
    # Puts new cards onto the player's battlefield that weren't in their deck: tokens
    # (which cease to exist when they leave the battlefield), token copies of another
    # card, catalog cards added by search, or made-up custom cards. Give exactly one of
    # `card_id`, `name` or `custom` ({ "name", "type_line", "power", "toughness" }).
    class ApplyCreateCard < BaseGameMutation
      MAX_COUNT = 20
      CUSTOM_FIELDS = %w[name type_line power toughness].freeze

      def call(table_slug:, seat_id:, card_id: nil, name: nil, custom: nil, token: true, count: 1, x: nil, y: nil)
        count = count.to_i
        return Failure[:validation_error, "Create between 1 and #{MAX_COUNT} cards"] unless count.between?(1, MAX_COUNT)

        source = step resolve_source(card_id, name, custom)
        step apply(table_slug) { |state| create(state, seat_id.to_s, source, token, count, x, y) }
      end

      private

      def resolve_source(card_id, name, custom)
        if custom.present?
          custom = custom.to_h.transform_keys(&:to_s).slice(*CUSTOM_FIELDS).transform_values { |v| v.to_s.strip.first(60) }
          return custom["name"].present? ? Success(custom: custom) : Failure[:validation_error, "A custom card needs a name"]
        end

        card = card_id.present? ? card_catalog.find_many([ card_id.to_i ])[card_id.to_i] : card_catalog.find_by_name(name.to_s)
        card ? Success(card_id: card.id) : Failure[:validation_error, "Unknown card: \"#{name || card_id}\""]
      end

      def create(state, seat_id, source, token, count, x, y)
        seat_state = state.seat(seat_id)
        return Failure[:not_found, "Seat has no game state yet"] unless seat_state

        count.times do |i|
          instance = Entities::CardInstance.new(
            card_id: source[:card_id], custom: source[:custom], owner_seat_id: seat_id, token: token,
            x: x && (x.to_f + i * 2), y: y && (y.to_f + i * 2)
          )
          instance = instance.with(sick: true) if creature?(instance)
          seat_state = seat_state.with_card(SecureRandom.hex(6), instance, zone: "battlefield")
        end

        new_state = state.with_seat(seat_id, seat_state)
        Success(append_log(new_state, seat_id: seat_id, event_type: "create_card",
                           payload: { "card_id" => source[:card_id], "custom_name" => source.dig(:custom, "name"),
                                      "count" => count, "token" => token }))
      end
    end
  end
end
