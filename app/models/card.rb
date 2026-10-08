class Card < ApplicationRecord
  validates :scryfall_oracle_id, presence: true, uniqueness: true
  validates :name, presence: true

  before_validation :normalize_name

  def legal_in?(format)
    legalities[format.to_s].in?(%w[legal restricted])
  end

  private

  def normalize_name
    return if name.blank?

    self.name_normalized = name.downcase.gsub(/[^a-z0-9]/, "")
    self.front_face_name_normalized = name.split(" // ").first.downcase.gsub(/[^a-z0-9]/, "")
  end
end
