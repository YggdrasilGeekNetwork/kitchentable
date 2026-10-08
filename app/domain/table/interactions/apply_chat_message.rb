module Table
  module Interactions
    class ApplyChatMessage < BaseGameMutation
      MAX_LENGTH = 500

      def call(table_slug:, seat_id:, message:)
        message = message.to_s.strip
        return Failure[:validation_error, "Messages must be 1-#{MAX_LENGTH} characters"] unless message.length.between?(1, MAX_LENGTH)

        step apply(table_slug) { |state| Success(append_log(state, seat_id: seat_id, event_type: "chat", payload: { "message" => message })) }
      end
    end
  end
end
