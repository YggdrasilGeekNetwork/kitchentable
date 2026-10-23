require "test_helper"

class DecklistSubmissionTest < ActionDispatch::IntegrationTest
  setup do
    @table = GameTable.create!(
      slug: "decklisttest", format: "commander", host_session_id: "host",
      max_seats: 4, last_activity_at: Time.current
    )
    @alice = @table.seats.create!(seat_number: 1, session_id: "alice", display_name: "Alice")
    @bob = @table.seats.create!(seat_number: 2, session_id: "bob", display_name: "Bob")
    Persistence::Redis::GameStateStore.new.delete(table_slug: @table.slug)
  end

  # Opening the seat URL is what gives this browser the seat (the signed cookie).
  def sit_as(seat) = get table_path(seat.game_table, seat: seat.token)

  # Turbo form submissions ask for turbo-stream first; the re-rendered HTML page must
  # still come back (Turbo swaps in a 422 HTML response) rather than a missing template.
  test "a failed submission re-renders the form with the pasted list and commander kept" do
    sit_as(@alice)

    post table_seat_decklist_path(@table, @alice),
      params: {
        mtg_format: "commander",
        raw_text: "1 Sol Ring\n1 Lightning Bolt", commander: "Tymna the Weaver", partner: "Thrasios, Triton Hero"
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_response :unprocessable_entity
    assert_select "textarea[name=raw_text]", text: "1 Sol Ring\n1 Lightning Bolt"
    assert_select "input[name=commander][value=?]", "Tymna the Weaver"
    assert_select "input[name=partner][value=?]", "Thrasios, Triton Hero"
    assert_select "input[type=file]", count: 0
    assert_select "input[name=url]", count: 0
  end

  # A page-level flash would sit under the open dialog's backdrop, out of sight.
  test "the reasons a deck was refused are listed inside the decklist dialog" do
    sit_as(@alice)

    post table_seat_decklist_path(@table, @alice),
      params: { mtg_format: "commander", raw_text: "1 Not A Real Card", commander: "Also Not Real" }

    assert_select "dialog .kt-form-error li", minimum: 1
    assert_match "Carta desconhecida", response.body
    assert_select ".kt-board[data-board-decklist-error-value=?]", "true"
    assert_select ".kt-flash", count: 0
  end

  test "only Commander tables show the commander field" do
    standard = GameTable.create!(slug: "standardtest", format: "standard", host_session_id: "host",
                                 max_seats: 4, last_activity_at: Time.current)
    seat = standard.seats.create!(seat_number: 1, session_id: "s", display_name: "Sam")
    sit_as(seat)

    post table_seat_decklist_path(standard, seat), params: { mtg_format: "standard", raw_text: "4 Opt" }

    assert_select "textarea[name=raw_text]"
    assert_select "input[name=commander]", count: 0
    assert_select "input[name=partner]", count: 0
  end

  test "submitting a deck for someone else's seat is refused before anything is dealt" do
    sit_as(@alice)

    post table_seat_decklist_path(@table, @bob), params: { mtg_format: "commander", raw_text: "1 Sol Ring", commander: "Sol Ring" }

    assert_redirected_to table_path(@table)
    assert_equal "Você só pode enviar o deck do seu próprio assento.", flash[:alert]
    assert_nil Persistence::Redis::GameStateStore.new.fetch(table_slug: @table.slug).seat(@bob.id.to_s)
  end

  test "submitting a deck without holding any seat at the table is refused" do
    post table_seat_decklist_path(@table, @alice), params: { mtg_format: "commander", raw_text: "1 Sol Ring", commander: "Sol Ring" }

    assert_redirected_to table_path(@table)
    assert_nil Persistence::Redis::GameStateStore.new.fetch(table_slug: @table.slug).seat(@alice.id.to_s)
  end

  test "the board warns that a new deck restarts your game" do
    sit_as(@alice)

    assert_select "dialog [data-board-target=decklistWarning][hidden]", text: /reinicia o seu jogo/
  end
end
