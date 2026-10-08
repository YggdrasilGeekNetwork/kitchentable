# Builds a table with seats, an in-memory game state and fake adapters for game
# interaction tests:
#
#   include GameTestHelper
#   setup { build_game(seats: { "1" => seat_state(hand: { "c1" => card(10) }) }) }
#   result = play(Table::Interactions::ApplyDraw, seat_id: "1", count: 2)
module GameTestHelper
  TableDouble = Struct.new(:slug, :seats, :format)
  SeatDouble = Struct.new(:id, :display_name, :seat_number)

  attr_reader :table_repo, :state_store, :broadcaster, :catalog

  def build_game(seats:, seat_numbers: seats.keys, active_seat_id: nil)
    @table_repo = Fakes::FakeTableRepository.new
    @state_store = Fakes::FakeGameStateStore.new
    @broadcaster = Fakes::FakeBroadcaster.new
    @catalog ||= Fakes::FakeCardCatalog.new

    seat_doubles = seat_numbers.each_with_index.map { |id, i| SeatDouble.new(id.to_i, "Player #{id}", i + 1) }
    @table_repo.register(TableDouble.new("table-1", seat_doubles, "commander"))
    state = seats.compact.reduce(Table::Entities::GameState.new(active_seat_id: active_seat_id)) { |s, (id, seat)| s.with_seat(id, seat) }
    @state_store.seed(table_slug: "table-1", state: state)
  end

  def card(card_id, owner: nil, **attrs) = Table::Entities::CardInstance.new(card_id: card_id, owner_seat_id: owner, **attrs)

  # Zones given as { instance_id => CardInstance }, in order (library: first = top).
  def seat_state(life_total: 20, **zones_and_attrs)
    zones = zones_and_attrs.slice(*Table::Entities::SeatState::ZONES.map(&:to_sym))
    attrs = zones_and_attrs.except(*zones.keys)
    Table::Entities::SeatState.new(
      life_total: life_total,
      zones: zones.to_h { |zone, cards| [ zone.to_s, cards.keys ] },
      instances: zones.values.reduce({}, :merge),
      **attrs
    )
  end

  def play(klass, **args)
    call_interaction(klass, deps: { table_repo: table_repo, state_store: state_store, broadcaster: broadcaster, card_catalog: catalog },
                     table_slug: "table-1", **args)
  end

  def state = state_store.fetch(table_slug: "table-1")
  def zone(seat_id, zone) = state.seat(seat_id).zones[zone]
  def last_log = state.log.last
end
