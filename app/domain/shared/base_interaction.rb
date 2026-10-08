module Shared
  # Reusable business logic, implemented as a Dry::Operation step-chain. This is the
  # actual "base operation" every Interaction inherits from.
  class BaseInteraction < Dry::Operation
    include Dry::Monads[:result]

    class << self
      # dry-operation 1.1.0 prepends #call so it always re-wraps its return value in
      # Success(...), even when that return value is already a Success/Failure — that
      # turns our own Success(x) into Success(Success(x)). `unwrap` undoes exactly that
      # one extra layer. It's applied by .call below for the common case (default,
      # production dependencies); tests that build an instance directly with injected
      # fakes must call it explicitly: `SomeInteraction.unwrap(instance.call(...))`.
      def call(...) = unwrap(new.call(...))

      def unwrap(outer)
        return outer unless outer.success?

        inner = outer.value!
        inner.is_a?(Dry::Monads::Result) ? inner : Dry::Monads::Result::Success.new(inner)
      end
    end

    private

    # Runs a dry-validation contract and normalizes its result into the same
    # Success/Failure[:tag, payload] shape every Interaction returns.
    def validate(contract_class, params)
      result = contract_class.new.call(params)
      result.success? ? Success(result.to_h) : Failure[:validation_error, result.errors.to_h]
    end
  end
end
