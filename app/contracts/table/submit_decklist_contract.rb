module Table
  class SubmitDecklistContract < Dry::Validation::Contract
    params do
      required(:format).filled(:string)
    end

    rule(:format) do
      key.failure("não suportado") unless ::GameTable::SUPPORTED_FORMATS.include?(value)
    end
  end
end
