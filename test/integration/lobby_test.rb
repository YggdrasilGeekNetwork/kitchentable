require "test_helper"

# The pages before the board: creating a table and joining one from its invite link.
class LobbyTest < ActionDispatch::IntegrationTest
  setup do
    @table = GameTable.create!(format: "commander", host_session_id: "host", max_seats: 2)
    @table.seats.create!(seat_number: 1, session_id: "host", display_name: "Alice")
  end

  test "the join page lists who is already seated and how many seats are taken" do
    get table_path(@table)

    assert_select ".kt-seat-list li", text: /Alice/
    assert_match "Commander · 1 de 2 lugares ocupados", response.body
    assert_select "form input[name=display_name][maxlength='40']"
  end

  test "a full table says so instead of offering a join form that would fail" do
    @table.seats.create!(seat_number: 2, session_id: "bob", display_name: "Bob")

    get table_path(@table)

    assert_select "input[name=display_name]", count: 0
    assert_match "Esta mesa está cheia", response.body
  end

  test "joining a table that filled up meanwhile explains it in Portuguese" do
    @table.seats.create!(seat_number: 2, session_id: "bob", display_name: "Bob")

    post table_seats_path(@table), params: { display_name: "Carol" }
    follow_redirect!

    assert_match "A mesa está cheia", response.body
  end

  test "invalid table settings come back with a readable field name" do
    post tables_path, params: { display_name: "Host", mtg_format: "commander", max_seats: 9 }
    follow_redirect!

    assert_match "Assentos: deve ser de 1 a 8", response.body
  end

  test "the board knows the table's size, so it only invites into free seats" do
    get table_path(@table, seat: @table.seats.first.token)

    assert_select ".kt-board[data-board-max-seats-value='2']"
  end
end
