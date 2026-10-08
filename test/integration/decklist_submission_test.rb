require "test_helper"

class DecklistSubmissionTest < ActionDispatch::IntegrationTest
  setup do
    @table = GameTable.create!(
      slug: "decklisttest", format: "commander", host_session_id: "host",
      max_seats: 4, last_activity_at: Time.current
    )
  end

  # Turbo form submissions ask for turbo-stream first; the re-rendered HTML page must
  # still come back (Turbo swaps in a 422 HTML response) rather than a missing template.
  test "a failed submission re-renders the form with the pasted list and commander kept" do
    post table_seat_decklist_path(@table, 999_999),
      params: {
        seat_id: 999_999, mtg_format: "commander",
        raw_text: "1 Sol Ring\n1 Lightning Bolt", commander: "Tymna the Weaver", partner: "Thrasios, Triton Hero"
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_response :unprocessable_entity
    assert_select "textarea[name=raw_text]", text: "1 Sol Ring\n1 Lightning Bolt"
    assert_select "input[name=commander][value=?]", "Tymna the Weaver"
    assert_select "input[name=partner][value=?]", "Thrasios, Triton Hero"
    assert_select "input[type=file]", count: 0
    assert_select "input[name=url]", count: 0
    assert_match "Seat not found", response.body
  end

  test "only Commander tables show the commander field" do
    standard = GameTable.create!(slug: "standardtest", format: "standard", host_session_id: "host",
                                 max_seats: 4, last_activity_at: Time.current)

    post table_seat_decklist_path(standard, 999_999), params: { seat_id: 999_999, mtg_format: "standard", raw_text: "4 Opt" }

    assert_select "textarea[name=raw_text]"
    assert_select "input[name=commander]", count: 0
    assert_select "input[name=partner]", count: 0
  end
end
