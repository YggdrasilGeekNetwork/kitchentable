require "test_helper"

class GameTableTest < ActiveSupport::TestCase
  def valid_attributes
    { format: "commander", host_session_id: SecureRandom.uuid, max_seats: 4 }
  end

  test "assigns a slug on create" do
    table = GameTable.create!(valid_attributes)
    assert table.slug.present?
  end

  test "to_param returns the slug, not the numeric id" do
    table = GameTable.create!(valid_attributes)
    assert_equal table.slug, table.to_param
  end

  test "rejects an unsupported format" do
    table = GameTable.new(valid_attributes.merge(format: "legacy"))
    assert_not table.valid?
  end

  test "rejects max_seats below 1" do
    table = GameTable.new(valid_attributes.merge(max_seats: 0))
    assert_not table.valid?
  end
end
