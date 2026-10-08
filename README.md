# Kitchen-Table

A self-hostable virtual tabletop for casual ("kitchen table") Magic: The Gathering —
pick a format, paste a decklist as plain text,
and play with friends remotely. No rules engine: the server is authoritative over
structural state (zones, life, counters) — players apply the rules themselves, same
model as Cockatrice/Untap.in/SpellTable.

## Deploy your own

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy)

Or self-host with Docker Compose:

```bash
cp .env.example .env   # set SECRET_KEY_BASE (bin/rails secret)
docker compose --profile with-datastores up
```

That starts Postgres + Redis + the web app + a background worker, all in one command.
Already have your own Postgres/Redis? Drop the `--profile with-datastores` and set
`DATABASE_URL` / `REDIS_URL` to point at them instead.

## Architecture

Rails 8 monolith, organized as explicit hexagonal layers (see
[herbertograca.com's Explicit Architecture](https://herbertograca.com/2017/11/16/explicit-architecture-01-ddd-hexagonal-onion-clean-cqrs-how-i-put-it-all-together/)):

- `app/domain/<context>/` — framework-free business logic: `entities/` (plain Ruby
  value objects), `ports/` (repository/adapter interfaces the domain depends on),
  `interactions/` (reusable dry-operation step-chains), `actions/` (thin public
  entrypoints for each use case).
- `app/infrastructure/` — concrete adapters implementing the ports: Postgres-backed
  repositories, the Redis-backed ephemeral game-state store, the ActionCable
  broadcaster.
- `app/channels`, `app/controllers` — the "driving" adapters: translate a WebSocket
  command or an HTTP request into an `Actions::X.call(...)`.

**Key design decision**: in-game state (life totals, zones, card positions, counters,
the recent event log) is **ephemeral**, held in Redis as one JSON blob per table —
not normalized Postgres rows. Postgres only stores the durable "session shape": which
tables and seats exist (`game_tables`, `seats`), plus the Scryfall card catalog
(`cards`). A table's Postgres row doubles as a cheap mutex (`with_lock`) guarding
concurrent Redis read-modify-write cycles for that table.

Every Action/Interaction returns a `Dry::Monads::Result` (`Success`/`Failure[:tag,
payload]`), validated with `dry-validation` contracts under `app/contracts/`.

## Dev setup

```bash
bundle install
bin/rails db:prepare
bin/dev
```

> Development and test only use the `primary` database role. Solid Cache/Queue (and
> their `cache`/`queue` roles, sharing production's single database) only exist in
> production — `bin/docker-entrypoint` loads their schemas there.

Needs a local Postgres and Redis (`docker run -d -p 6379:6379 redis:7-alpine` if you
don't have one). Run `bin/rails test` for the suite.

## Syncing card data

```bash
bin/rails runner 'CardCatalog::Actions::SyncCardCatalog.call'
```

Pulls Scryfall's `oracle_cards` bulk data into the `cards` table (legalities, color
identity, etc. come straight from Scryfall — no hand-maintained ban lists). Runs
automatically on a daily recurring job in production (`config/recurring.yml`) and
once on first boot if the `cards` table is empty (`db/seeds.rb`).

See `ROADMAP.md` for what's built vs. what's next (A/V calling, OBS overlay).
