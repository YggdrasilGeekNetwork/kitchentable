class DecklistsController < ApplicationController
  include HandlesDomainResult
  include SeatSession

  # Plain pasted text only; for Commander tables the commander (and an optional
  # Partner/Background) come from their own fields.
  #
  # The seat is the one this browser holds (seat token in the URL or the signed
  # cookie) — never the id in the route or the form, which anyone could edit.
  def create
    table = ::GameTable.find_by!(slug: params[:table_slug])
    seat = seat_from_session(table)
    return reject_foreign_seat(table) unless seat && seat.id.to_s == params[:seat_id].to_s

    result = Table::Actions::SubmitDecklist.call(
      table_slug: table.slug,
      seat_id: seat.id,
      format: params[:mtg_format],
      raw_text: params[:raw_text].to_s,
      commander_names: [ params[:commander], params[:partner] ].compact_blank,
      ignore_deck_size: params[:ignore_deck_size] == "1"
    )

    if result.success?
      redirect_to table_url_for_seat(table, seat), notice: "Deck enviado"
    elsif request.format.json?
      render_failure(result)
    else
      rerender_form(table, seat, result)
    end
  end

  private

  def reject_foreign_seat(table)
    respond_to do |format|
      format.html { redirect_to table_path(table), status: :see_other, alert: "Você só pode enviar o deck do seu próprio assento." }
      format.json { render json: { error: "Você só pode enviar o deck do seu próprio assento." }, status: :forbidden }
    end
  end

  # Re-renders the table page instead of redirecting, so the pasted list and the
  # chosen commander survive a failed submission. The error is shown inside the
  # decklist dialog: a page-level flash would sit under the modal's backdrop. When the
  # card count is the only problem, it's a warning instead, with a button to play the
  # deck anyway.
  def rerender_form(table, seat, result)
    @table = table
    @seat_id = seat.id
    @seat_token = seat.token
    @raw_text = params[:raw_text]
    @commander = params[:commander]
    @partner = params[:partner]
    if deck_size_only?(result)
      @deck_size_warning = failure_messages(result).first
    else
      @decklist_errors = failure_messages(result)
    end
    render "tables/show", layout: "board", status: :unprocessable_entity
  end

  def deck_size_only?(result)
    tag, errors = result.failure
    tag == :validation_error && errors.is_a?(Array) && errors.any? &&
      errors.all? { |e| e.is_a?(Hash) && e[:type] == "deck_size" }
  end
end
