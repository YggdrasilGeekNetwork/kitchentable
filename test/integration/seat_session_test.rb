require "test_helper"

# The seat's secret token rides in the table URL so a player can always get back to
# their seat — after losing cookies, or from another browser.
class SeatSessionTest < ActionDispatch::IntegrationTest
  setup do
    @table = GameTable.create!(format: "commander", host_session_id: "host", max_seats: 4)
    @seat = @table.seats.create!(seat_number: 1, session_id: "someone", display_name: "Alice")
  end

  test "creating a table lands on the table URL carrying the host's seat token" do
    post tables_path, params: { display_name: "Host", mtg_format: "commander", max_seats: 4 }

    table = GameTable.order(:created_at).last
    assert_redirected_to table_path(table, seat: table.seats.first.token)
  end

  test "joining a table lands on the table URL carrying the new seat's token" do
    post table_seats_path(@table), params: { display_name: "Bob" }

    bob = @table.seats.find_by!(display_name: "Bob")
    assert_redirected_to table_path(@table, seat: bob.token)
  end

  test "the seat URL opens the board in a browser with no cookies for it" do
    get table_path(@table, seat: @seat.token)

    assert_response :success
    assert_select ".kt-board[data-board-seat-id-value=?][data-board-seat-token-value=?]", @seat.id.to_s, @seat.token
  end

  test "the bare table URL goes back to the seat URL once the browser knows the seat" do
    get table_path(@table, seat: @seat.token)
    get table_path(@table)

    assert_redirected_to table_path(@table, seat: @seat.token)
  end

  test "the invite link on the board is the bare table URL, never the seat URL" do
    get table_path(@table, seat: @seat.token)

    assert_select ".kt-board[data-board-invite-url-value=?]", table_url(@table)
  end

  test "an unknown seat token shows the join form with a warning" do
    get table_path(@table, seat: "not-a-real-token")

    assert_response :success
    assert_select "input[name=display_name]"
    assert_select ".kt-board", count: 0
    assert_match "não é válido", response.body
  end

  test "a numeric seat id in the URL doesn't open someone's seat" do
    get table_path(@table, seat: @seat.id)

    assert_select ".kt-board", count: 0
  end
end
