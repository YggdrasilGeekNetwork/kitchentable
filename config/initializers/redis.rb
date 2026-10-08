# Shared connection pool for the ephemeral game-state store (Infrastructure::Persistence::Redis::GameStateStore).
# Action Cable uses its own Redis connection configured separately in config/cable.yml —
# that pool is for the game-state payload, not pub/sub.
#
# Test env defaults to DB index 2 (distinct from dev's 0 and cable's 1) so test runs can
# `flushdb` freely without touching development data.
default_redis_url = Rails.env.test? ? "redis://localhost:6379/2" : "redis://localhost:6379/0"

REDIS_POOL = ConnectionPool.new(size: ENV.fetch("RAILS_MAX_THREADS", 5).to_i, timeout: 5) do
  Redis.new(url: ENV.fetch("REDIS_URL", default_redis_url))
end
