require "test_helper"

class SafeUrlFetcherTest < ActiveSupport::TestCase
  setup { @fetcher = Http::SafeUrlFetcher.new }

  test "rejects non-https URLs" do
    assert_raises(Http::SafeUrlFetcher::UnsafeUrlError) { @fetcher.fetch("http://example.com/deck.txt") }
  end

  test "rejects URLs resolving to loopback addresses" do
    assert_raises(Http::SafeUrlFetcher::UnsafeUrlError) { @fetcher.fetch("https://localhost/deck.txt") }
  end

  test "rejects a literal private-network IP host" do
    assert_raises(Http::SafeUrlFetcher::UnsafeUrlError) { @fetcher.fetch("https://10.0.0.5/deck.txt") }
  end

  test "rejects a literal link-local IP host" do
    assert_raises(Http::SafeUrlFetcher::UnsafeUrlError) { @fetcher.fetch("https://169.254.169.254/latest/meta-data") }
  end

  test "rejects URLs with no resolvable host" do
    assert_raises(Http::SafeUrlFetcher::UnsafeUrlError) do
      @fetcher.fetch("https://this-domain-should-not-exist-kitchentable-test.invalid/deck.txt")
    end
  end
end
