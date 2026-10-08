# CLAUDE.md — Kitchen-Table Project Context

Self-hostable MTG virtual tabletop. See `README.md` for setup/architecture overview and
`ROADMAP.md` for what's built vs. planned. This file is pitfalls/conventions only.

## Commit style

Same as the Arkheion monorepo: one-liner messages, conventional prefixes
(`feat`/`fix`/`chore`/`refactor`), no `Co-Authored-By`.

## Testing policy

Every code change ships with Minitest coverage in `test/`, run via `bin/rails test`.
Interaction/Action tests inject fakes from `test/support/fakes/` via the
`call_interaction(klass, *args, deps: {}, **kwargs)` helper (see `test/test_helper.rb`)
— **never** call `SomeInteraction.new(deps).call(...)` directly in a test, see the
dry-operation pitfall below.

## Architecture — read this before adding a new use case

- `app/domain/<context>/actions/` — one class per use case, thin: `def call(...) =
  Interactions::X.call(...)`. These are the only things channels/controllers call.
- `app/domain/<context>/interactions/` — the actual logic, `< Shared::BaseInteraction`
  (a `Dry::Operation` subclass), `step`-chained, dependencies injected via `initialize`
  defaults pointing at real adapters.
- `app/domain/<context>/ports/` — abstract interfaces (`NotImplementedError` stubs).
  Never reference `app/infrastructure` or `ActiveRecord` from here.
- `app/infrastructure/` — concrete adapters. **Not** namespaced under `Infrastructure::`
  — see Zeitwerk note below.
- Game state (life, zones, card instances, counters, the event log) is **ephemeral**,
  one JSON blob per table in Redis (`Persistence::Redis::GameStateStore`). Postgres only
  holds `cards` (catalog), `game_tables`/`seats` (session shape). Don't add new
  persisted-by-default game-state columns — if it changes during a game, it belongs in
  the Redis blob (`Table::Entities::GameState`/`SeatState`/`CardInstance`), not a migration.

## Game commands & what players see

- Every game-state change is a `Table::Interactions::ApplyX < BaseGameMutation` that
  does `step apply(table_slug) { |state| ...Success(new_state) / Failure... }`. `apply`
  locks, fetches, saves and then pushes **every seat its own** `TableView`. Don't
  broadcast from interactions yourself, and don't use `step` inside the `apply` block
  (it exits by `throw`, which must not unwind through the row-lock transaction).
- `Table::Views::TableView` is the **only** place hidden information is redacted
  (hands, libraries, face-down cards, peeks, reveals). New state that some players
  mustn't see goes through it, with a test in `test/domain/table/views/`.
- A seat is identified by its secret `token` (`?seat=` in the table URL, the
  `seat_for_<slug>` cookie, and `TableChannel`'s `seat_token` param) — never by its
  numeric id, which anyone could edit. Invite links are the bare table URL; never
  share `window.location` from the board.
- Interaction tests use `GameTestHelper` (`test/support/game_test_helper.rb`):
  `build_game(seats: { "1" => seat_state(hand: { "c1" => card(10) }) })` then
  `play(Klass, seat_id: "1", ...)`.

## Zeitwerk rules — CRITICAL

Every top-level folder under `app/` is its own Zeitwerk root by default — it does
**not** get wrapped in a module matching the folder name. `app/infrastructure/
persistence/redis/game_state_store.rb` must define `Persistence::Redis::
GameStateStore`, **not** `Infrastructure::Persistence::Redis::GameStateStore` (the
latter was the original design and broke `zeitwerk:check`; don't reintroduce it without
also adding a `Rails.autoloaders.main.push_dir(..., namespace: Infrastructure)` in
`config/application.rb`, which was deliberately avoided here to keep things boring).

Avoid naming a nested module the same as a real top-level gem constant —
`Persistence::ActiveRecord` would shadow `::ActiveRecord` inside that namespace and any
bare `ActiveRecord::Base` reference there would silently resolve wrong (or raise
`NameError`). That's why the Postgres adapters live under `Persistence::Postgres::`,
not `Persistence::ActiveRecord::`.

## dry-operation double-wrap pitfall

`Shared::BaseInteraction < Dry::Operation`. dry-operation 1.1.0 prepends `#call` so it
**always** re-wraps the return value in `Success(...)`, even if that value is already a
`Success`/`Failure` — so a plain `Success(x)` return becomes `Success(Success(x))`.
`BaseInteraction.call` (the class method) undoes exactly that one extra layer via
`unwrap`. This means:

- Production code must go through `SomeInteraction.call(...)` (class method), never
  `SomeInteraction.new.call(...)` directly.
- Tests that need injected fake dependencies must use the `call_interaction` test
  helper (which calls `klass.unwrap(klass.new(**deps).call(...))`) — calling
  `.new(deps).call(...)` directly skips the unwrap and silently double-wraps.

## dry-monads pattern-matching pitfall

`in Dry::Monads::Success(value)` destructures an **Array** value into its elements:
`Success([a])` binds `value = a`, and `Success([a, b])` doesn't match at all. When a
result can hold a list, use `result.success?` / `result.value!` instead of `case/in`
(see `TableChannel#handle_result`).

## ActionCable `transmit` pitfall

`transmit` takes one **positional** Hash argument (`transmit(data, via: nil)`). Calling
`transmit(error: "x", payload: y)` is parsed as all-keywords with zero positional args
and raises `ArgumentError: wrong number of arguments (given 0, expected 1)`. Always
`transmit({ ... })` explicitly.

## Multi-database gotcha: `db:prepare` does not cascade across shared-database roles

`config/database.yml` intentionally points `primary`/`cache`/`queue` at the **same**
physical Postgres database (one `DATABASE_URL`, just different `migrations_paths`) so
self-hosting only needs one Postgres instance. Confirmed by testing: `bin/rails
db:prepare` only prepares the `primary` role in that setup — it silently does **not**
cascade into `cache`/`queue`. Always follow it with
`bin/rails db:schema:load:cache db:schema:load:queue` (both are no-ops if already
loaded — safe to run on every boot). `bin/docker-entrypoint` already does this.

That shared-database shape is **production-only**. Development/test declare just
`primary` — don't add `cache`/`queue` roles back there. With all three roles on one
physical database, `db:migrate` dumps the *whole* database into `cache_schema.rb`/
`queue_schema.rb` (clobbering the Solid templates), and test boots purge + reload the
shared test database once per role, so the last schema loaded wins and tests see a
stale `cards` table. `db/cache_schema.rb`/`db/queue_schema.rb` must stay the gems'
templates (`lib/generators/solid_{cache,queue}/install/templates/db/`).

## Toolchain gotcha: `json` gem 3.x breaks ActiveSupport::JSON on this Rails version

`json` 3.0+ dropped the `quirks_mode` keyword that `activesupport` 8.0.5's JSON encoder
still passes, breaking `ActiveSupport::JSON.encode` (and anything using it — jsonb
columns, `bin/importmap pin`, migrations with jsonb columns) with `ArgumentError:
unknown keyword: quirks_mode`. Gemfile pins `gem "json", "~> 2.10"` — don't remove it
or let it drift to 3.x without confirming this is fixed upstream.

## Ruby 3.4 / dry-schema pitfalls (inherited from the Arkheion monorepo conventions)

- `yield method do...end` is a SyntaxError in Ruby 3.4 — use `yield method { ... }`.
- dry-schema `.array` needs a type: `.array(:hash)`, not bare `.array`.
