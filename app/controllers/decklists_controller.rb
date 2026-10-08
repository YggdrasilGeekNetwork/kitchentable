class DecklistsController < ApplicationController
  include HandlesDomainResult
  include SeatSession

  # Plain pasted text only; for Commander tables the commander (and an optional
  # Partner/Background) come from their own fields.
  def create
    table = ::GameTable.find_by!(slug: params[:table_slug])

    result = Table::Actions::SubmitDecklist.call(
      table_slug: table.slug,
      seat_id: params[:seat_id],
      format: params[:mtg_format],
      raw_text: params[:raw_text].to_s,
      commander_names: [ params[:commander], params[:partner] ].compact_blank
    )

    if result.success?
      redirect_to table_url_for_seat(table, table.seats.find(params[:seat_id])), notice: "Deck enviado"
    elsif request.format.json?
      render_failure(result)
    else
      rerender_form(table, result)
    end
  end

  private

  # Re-renders the table page instead of redirecting, so the pasted list and the
  # chosen commander survive a failed submission.
  def rerender_form(table, result)
    @table = table
    @seat_id = params[:seat_id]
    @seat_token = table.seats.find_by(id: params[:seat_id])&.token
    @raw_text = params[:raw_text]
    @commander = params[:commander]
    @partner = params[:partner]
    flash.now[:alert] = failure_status_and_message(result).last
    render "tables/show", layout: "board", status: :unprocessable_entity
  end
end
