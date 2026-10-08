class TablesController < ApplicationController
  include HandlesDomainResult
  include SeatSession

  def new; end

  def create
    result = Table::Actions::CreateTable.call(
      format: params[:mtg_format],
      host_session_id: current_guest_id,
      host_display_name: params[:display_name],
      name: params[:name].presence,
      max_seats: (params[:max_seats] || 4).to_i
    )

    if result.success?
      table = result.value![:table]
      seat = result.value![:seat]
      remember_seat(table, seat)
      redirect_to table_url_for_seat(table, seat)
    else
      render_failure(result)
    end
  end

  # Seated players get the full-screen board — always at the URL carrying their seat
  # token, so a reload or a bookmark gets them back. Everyone else gets the join form.
  def show
    @table = ::GameTable.find_by!(slug: params[:slug])
    seat = seat_from_session(@table)

    if params[:seat].present? && seat.nil?
      flash.now[:alert] = "Esse link de assento não é válido para esta mesa."
    elsif seat && params[:seat] != seat.token
      return redirect_to table_url_for_seat(@table, seat)
    end

    if seat
      remember_seat(@table, seat)
      @seat_id = seat.id
      @seat_token = seat.token
    end
    render layout: seat ? "board" : "application"
  end
end
