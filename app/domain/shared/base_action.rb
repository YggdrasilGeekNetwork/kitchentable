module Shared
  # Entrypoint for a use case. Plain orchestrator — no Dry::Operation step-chain here,
  # it just delegates to one or more Interactions and returns their Result untouched.
  class BaseAction
    include Dry::Monads[:result, :do]

    class << self
      def call(...) = new.call(...)
    end
  end
end
