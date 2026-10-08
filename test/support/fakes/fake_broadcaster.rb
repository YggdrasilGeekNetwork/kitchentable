module Fakes
  # Records broadcasts instead of touching ActionCable, so tests can assert exactly
  # which view each seat's private stream would have received.
  class FakeBroadcaster < Table::Ports::BroadcasterPort
    Broadcast = Struct.new(:table_slug, :seat_id, :payload, keyword_init: true)

    attr_reader :seat_broadcasts

    def initialize
      @seat_broadcasts = []
    end

    # The last view pushed to a seat.
    def view_for(seat_id) = @seat_broadcasts.reverse.find { |b| b.seat_id == seat_id.to_s }&.payload

    def broadcast_to_seat(table_slug:, seat_id:, payload:)
      @seat_broadcasts << Broadcast.new(table_slug: table_slug, seat_id: seat_id, payload: payload)
    end
  end
end
