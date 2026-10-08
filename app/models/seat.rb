class Seat < ApplicationRecord
  enum :status, { joined: 0, disconnected: 1, left: 2 }

  belongs_to :game_table

  # Secret that identifies the seat in the table URL — never the numeric id, which
  # anyone could change to take someone else's seat.
  has_secure_token :token

  validates :seat_number, presence: true, uniqueness: { scope: :game_table_id }
  validates :session_id, presence: true, uniqueness: { scope: :game_table_id }
  validates :display_name, presence: true

  before_validation :touch_last_seen, on: :create

  private

  def touch_last_seen
    self.last_seen_at ||= Time.current
  end
end
