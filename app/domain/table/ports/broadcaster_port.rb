module Table
  module Ports
    # Real-time fan-out to one seat's private stream. Every payload is that seat's own
    # Table::Views::TableView — this port only moves already-redacted payloads, it
    # never decides what's hidden.
    class BroadcasterPort
      def broadcast_to_seat(table_slug:, seat_id:, payload:)
        raise NotImplementedError
      end
    end
  end
end
