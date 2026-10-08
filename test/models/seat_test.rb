require "test_helper"

class SeatTest < ActiveSupport::TestCase
  def table
    @table ||= GameTable.create!(format: "commander", host_session_id: SecureRandom.uuid, max_seats: 4)
  end

  test "enforces one seat number per table" do
    table.seats.create!(seat_number: 1, session_id: "a", display_name: "Alice")
    dup = table.seats.new(seat_number: 1, session_id: "b", display_name: "Bob")

    assert_not dup.valid?
  end

  test "enforces one seat per session per table" do
    table.seats.create!(seat_number: 1, session_id: "a", display_name: "Alice")
    dup = table.seats.new(seat_number: 2, session_id: "a", display_name: "Alice Again")

    assert_not dup.valid?
  end
end
