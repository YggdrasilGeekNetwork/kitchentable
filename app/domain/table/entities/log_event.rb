module Table
  module Entities
    class LogEvent
      attr_reader :sequence, :seat_id, :event_type, :payload, :at

      def initialize(sequence:, seat_id:, event_type:, payload: {}, at: Time.current)
        @sequence = sequence
        @seat_id = seat_id
        @event_type = event_type.to_s
        @payload = payload
        @at = at
      end

      def to_h
        { "sequence" => sequence, "seat_id" => seat_id, "event_type" => event_type, "payload" => payload, "at" => at.iso8601 }
      end

      def self.from_h(hash)
        new(
          sequence: hash["sequence"],
          seat_id: hash["seat_id"],
          event_type: hash["event_type"],
          payload: hash["payload"] || {},
          at: hash["at"] ? Time.zone.parse(hash["at"]) : Time.current
        )
      end
    end
  end
end
