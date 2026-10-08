require "test_helper"

class GameStateTest < ActiveSupport::TestCase
  test "round-trips through to_h/from_h" do
    state = Table::Entities::GameState.blank
    seat_state = Table::Entities::SeatState.new(life_total: 35)
    state = state.with_seat("1", seat_state)

    rebuilt = Table::Entities::GameState.from_h(state.to_h)

    assert_equal 35, rebuilt.seat("1").life_total
  end

  test "caps the log at LOG_CAP entries" do
    state = Table::Entities::GameState.blank

    (Table::Entities::GameState::LOG_CAP + 10).times do |i|
      event = Table::Entities::LogEvent.new(sequence: i, seat_id: "1", event_type: "noop")
      state = state.with_log_event(event)
    end

    assert_equal Table::Entities::GameState::LOG_CAP, state.log.size
    assert_equal 10, state.log.first.sequence
  end

  test "next_sequence increments from the last log entry" do
    state = Table::Entities::GameState.blank
    assert_equal 1, state.next_sequence

    state = state.with_log_event(Table::Entities::LogEvent.new(sequence: 1, seat_id: "1", event_type: "noop"))
    assert_equal 2, state.next_sequence
  end
end
