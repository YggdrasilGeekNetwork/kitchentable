module GuestSession
  extend ActiveSupport::Concern

  included do
    before_action :ensure_guest_session
  end

  private

  def ensure_guest_session
    cookies.signed[:guest_session] ||= {
      value: { guest_id: SecureRandom.uuid },
      expires: 30.days,
      httponly: true,
      same_site: :lax
    }
  end

  def current_guest_id
    cookies.signed[:guest_session]["guest_id"]
  end
end
