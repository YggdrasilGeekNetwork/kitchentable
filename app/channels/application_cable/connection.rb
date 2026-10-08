module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :guest_id

    def connect
      self.guest_id = guest_session_id || reject_unauthorized_connection
    end

    private

    def guest_session_id
      cookies.signed[:guest_session]&.dig("guest_id")
    end
  end
end
