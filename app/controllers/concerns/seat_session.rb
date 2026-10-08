# Which seat this browser plays at a table. The seat's secret token lives in the URL
# (?seat=...) so the session survives lost cookies or a different browser; a signed
# cookie remembers it too, so opening the bare table link still finds the seat.
module SeatSession
  extend ActiveSupport::Concern

  SEAT_COOKIE_TTL = 30.days

  private

  def remember_seat(table, seat)
    cookies.signed[seat_cookie_name(table)] = { value: seat.token, expires: SEAT_COOKIE_TTL, httponly: true, same_site: :lax }
  end

  def table_url_for_seat(table, seat)
    table_path(table, seat: seat.token)
  end

  # From the URL token first, then the cookie. Cookies written before seat tokens
  # existed hold the seat id; those are only honored for the guest who sat there.
  def seat_from_session(table)
    from_url = params[:seat].presence && table.seats.find_by(token: params[:seat])
    return from_url if from_url

    remembered = cookies.signed[seat_cookie_name(table)]
    return nil if remembered.blank?

    table.seats.find_by(token: remembered.to_s) ||
      table.seats.find_by(id: remembered.to_s, session_id: current_guest_id)
  end

  def seat_cookie_name(table) = "seat_for_#{table.slug}"
end
