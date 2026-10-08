module Table
  class JoinTableContract < Dry::Validation::Contract
    params do
      required(:table_slug).filled(:string)
      required(:display_name).filled(:string, min_size?: 1, max_size?: 40)
    end
  end
end
