module Table
  class CreateTableContract < Dry::Validation::Contract
    params do
      optional(:name).maybe(:string)
      required(:format).filled(:string)
      required(:max_seats).filled(:integer)
      required(:host_display_name).filled(:string, min_size?: 1, max_size?: 40)
    end

    rule(:format) do
      key.failure("unsupported format") unless ::GameTable::SUPPORTED_FORMATS.include?(value)
    end

    rule(:max_seats) do
      key.failure("must be between 1 and 8") unless value.between?(1, 8)
    end
  end
end
