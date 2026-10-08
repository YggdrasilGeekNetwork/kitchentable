module Table
  class SubmitDecklistContract < Dry::Validation::Contract
    params do
      required(:format).filled(:string)
    end

    rule(:format) do
      key.failure("unsupported format") unless ::GameTable::SUPPORTED_FORMATS.include?(value)
    end
  end
end
