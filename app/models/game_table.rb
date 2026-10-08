class GameTable < ApplicationRecord
  SUPPORTED_FORMATS = %w[commander standard].freeze

  enum :status, { lobby: 0, active: 1, completed: 2, abandoned: 3 }

  has_many :seats, dependent: :destroy

  validates :slug, presence: true, uniqueness: true
  validates :format, inclusion: { in: SUPPORTED_FORMATS }
  validates :host_session_id, presence: true
  validates :max_seats, numericality: { greater_than: 0 }

  before_validation :assign_slug, on: :create
  before_validation :touch_last_activity, on: :create

  def to_param = slug

  private

  def assign_slug
    self.slug ||= SecureRandom.alphanumeric(10).downcase
  end

  def touch_last_activity
    self.last_activity_at ||= Time.current
  end
end
