require "net/http"
require "resolv"
require "ipaddr"

module Http
  # SSRF-safe GET fetcher for outbound HTTP (today: the Scryfall catalog sync). Kept
  # strict even for hardcoded URLs, since self-hosted instances may run on a home
  # network where an internal IP is reachable.
  #
  # Safe by construction, not by blocklist:
  #   - https only
  #   - every resolved IP for the host must be public (rejects private/loopback/link-local)
  #   - Net::HTTP does not follow redirects here, so a 3xx response is just a failure —
  #     no "safe host redirects to an internal IP" bypass
  #   - short timeout + response size cap
  class SafeUrlFetcher
    # Small by default; fetches of known larger payloads (e.g. the Scryfall bulk-data
    # sync) pass a bigger `max_bytes:` explicitly.
    DEFAULT_MAX_BYTES = 2.megabytes
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30

    class UnsafeUrlError < StandardError; end

    def initialize(max_bytes: DEFAULT_MAX_BYTES)
      @max_bytes = max_bytes
    end

    def fetch(url)
      uri = validate!(url)

      response = ::Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
      ) { |http| http.request(::Net::HTTP::Get.new(uri)) }

      raise UnsafeUrlError, "unexpected response: #{response.code}" unless response.is_a?(::Net::HTTPSuccess)

      body = response.body.to_s
      raise UnsafeUrlError, "response too large" if body.bytesize > @max_bytes

      body
    end

    private

    def validate!(url)
      uri = URI.parse(url)
      raise UnsafeUrlError, "only https URLs are allowed" unless uri.is_a?(URI::HTTPS)
      raise UnsafeUrlError, "missing host" if uri.host.blank?

      addresses = begin
        Resolv.getaddresses(uri.host)
      rescue Resolv::ResolvError
        raise UnsafeUrlError, "could not resolve host"
      end
      raise UnsafeUrlError, "could not resolve host" if addresses.empty?

      addresses.each do |address|
        ip = IPAddr.new(address)
        if ip.private? || ip.loopback? || ip.link_local?
          raise UnsafeUrlError, "URL resolves to a private or internal address"
        end
      end

      uri
    end
  end
end
