ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

Dir[Rails.root.join("test/support/**/*.rb")].sort.each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Instantiates a Shared::BaseInteraction subclass with injected (fake) dependencies
    # and calls it, applying the same dry-operation double-wrap unwrap that `klass.call`
    # applies for the default-dependency production path. Use this instead of
    # `klass.new(**deps).call(...)` directly — that skips the unwrap entirely.
    def call_interaction(klass, *args, deps: {}, **kwargs)
      klass.unwrap(klass.new(**deps).call(*args, **kwargs))
    end
  end
end
