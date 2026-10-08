require "test_helper"

class SeatStateTest < ActiveSupport::TestCase
  test "defaults every zone to an empty array" do
    seat_state = Table::Entities::SeatState.new

    assert_equal Table::Entities::SeatState::ZONES, seat_state.zones.keys
    assert_empty seat_state.zones["hand"]
  end

  test "zone_of finds which zone holds a card instance" do
    seat_state = Table::Entities::SeatState.new(zones: { "hand" => [ "ci_1" ], "battlefield" => [] })

    assert_equal "hand", seat_state.zone_of("ci_1")
    assert_nil seat_state.zone_of("unknown")
  end

  test "with_* methods return a new instance without mutating the original" do
    original = Table::Entities::SeatState.new(life_total: 20)
    changed = original.with_life_total(15)

    assert_equal 20, original.life_total
    assert_equal 15, changed.life_total
  end
end
