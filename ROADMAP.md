# Roadmap

## Built (this pass)

- Hexagonal domain layer (`app/domain/{table,card_catalog}`) with `Shared::BaseAction`/
  `Shared::BaseInteraction`, dry-monads/dry-operation/dry-validation throughout.
- Ports + adapters: Postgres repositories (`GameTable`/`Seat`/`Card`), Redis-backed
  ephemeral `GameState` store, ActionCable broadcaster. Decklists are plain pasted
  text only (file upload and deck-site links were removed — Moxfield's API is
  Cloudflare-gated against server-side requests anyway); for Commander, the commander
  is picked in its own field rather than by a section of the list.
- Use cases: `CreateTable`, `JoinTable`, `SubmitDecklist` (parse → validate → deal),
  plus the full table command set — move (incl. control changes), tap/untap all, draw,
  mill, shuffle, keep/mulligan, life, player & card counters, transform, face down,
  reveal, peek at any library's top N, tokens, dice, pass turn, chat.
- Commander + Standard deck validation against Scryfall-synced legalities/color identity.
- Per-seat redacted views (`Table::Views::TableView`): after every change each seat
  gets its own snapshot on its private stream; hidden zones never leave the server.
- Goldfish-style board (`board_controller.js`): 2/3 of the screen for you, 1/3 split
  between up to three opponents; Arena-style permanents (art crop + P/T, full card on
  hover); double-click from hand auto-places by type (lands / other / creatures) or
  casts instants and sorceries onto a stack to resolve; right-click menus for the
  battlefield (tap/untap all, new turn, proliferate, tokens, card search, custom
  cards) and for cards (move, counters, P/T modifiers, transform, token copies,
  remove); opening-hand keep/mulligan screen; shortcuts D/U/S/N/T; log + chat.
- Deploy: `Dockerfile`, `docker-compose.yml`, `render.yaml`, Scryfall self-seed + daily
  recurring sync.

## Follow-ups

- Board: undo (needs per-table state history, and a rule for when another player
  acted since), select all / multi-select drag, attachments (auras, equipment),
  sleeves, touch support.
- Partner/Background pairing isn't validated (any two cards are accepted).
- `bin/docker-entrypoint` reloads `queue_schema.rb` (which recreates Solid Queue's
  tables) on every boot — pending jobs are lost on each deploy.

## Phase 2 — Audio/video calling (`ENABLE_AV`)

WebRTC mesh, signaling relayed through a new `AvSignalingChannel` (ActionCable), gated
by `ENABLE_AV=false` by default. Not started — no stub channel exists yet either.

## Phase 3 — OBS overlay (`ENABLE_OVERLAY`)

Token-authenticated read-only browser-source view streaming life totals/turn state via
a new `OverlayChannel`. Not started.

## Explicitly out of scope (product decisions, not gaps)

- No rules engine (stack, triggers, replacement effects) — players self-enforce, same
  model as Cockatrice/Untap.in.
- No deckbuilder (card search, categories, mana curve) — that's Moxfield/Archidekt's
  job; this app only imports from them.
- No persistent accounts or saved deck library — guest cookie only; decklists are
  resubmitted per table session, never stored.
- No durable game log/audit trail — the event log is an ephemeral, capped ring buffer
  in Redis alongside the rest of the game state.
