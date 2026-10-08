class SeatsController < ApplicationController
  include HandlesDomainResult
  include SeatSession

  def create
    table = ::GameTable.find_by!(slug: params[:table_slug])

    result = Table::Actions::JoinTable.call(
      table_slug: table.slug,
      session_id: current_guest_id,
      display_name: params[:display_name]
    )

    if result.success?
      seat = result.value![:seat]
      remember_seat(table, seat)
      redirect_to table_url_for_seat(table, seat)
    else
      render_failure(result)
    end
  end
end
