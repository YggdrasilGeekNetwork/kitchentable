module Broadcasting
  class ActionCableBroadcaster < Table::Ports::BroadcasterPort
    def broadcast_to_seat(table_slug:, seat_id:, payload:)
      ActionCable.server.broadcast(seat_stream(table_slug, seat_id), payload)
    end

    def self.seat_stream_name(table_slug, seat_id) = new.seat_stream(table_slug, seat_id)

    def seat_stream(table_slug, seat_id) = "table_#{table_slug}_seat_#{seat_id}"
  end
end
