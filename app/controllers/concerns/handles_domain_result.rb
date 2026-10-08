module HandlesDomainResult
  extend ActiveSupport::Concern

  private

  def render_failure(result)
    status, message = failure_status_and_message(result)

    respond_to do |format|
      format.html { redirect_back_or_to(root_path, status: :see_other, alert: message) }
      format.json { render json: { error: message }, status: status }
    end
  end

  def failure_status_and_message(result)
    case result
    in Dry::Monads::Failure[ :not_found, message ]
      [ :not_found, message ]
    in Dry::Monads::Failure[ :table_full, message ]
      [ :conflict, message ]
    in Dry::Monads::Failure[ :validation_error, errors ]
      [ :unprocessable_entity, summarize_errors(errors) ]
    in Dry::Monads::Failure[ :persistence_error, errors ]
      [ :unprocessable_entity, summarize_errors(errors) ]
    in Dry::Monads::Failure[ _tag, message ]
      [ :unprocessable_entity, message.to_s ]
    end
  end

  def summarize_errors(errors)
    case errors
    when Array
      errors.map { |e| e.is_a?(Hash) ? e[:message] || e["message"] : e.to_s }.join("; ")
    when Hash
      errors.map { |field, messages| "#{field}: #{Array(messages).join(', ')}" }.join("; ")
    else
      errors.to_s
    end
  end
end
