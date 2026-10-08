import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { fill, h } from "board/dom"
import { describeEvent, seatName } from "board/log"

// The game board. Everything on screen is drawn from the latest TableView the server
// pushed for this seat (see Table::Views::TableView) — the client keeps no game state
// of its own, it only sends commands and redraws on the next view.
//
// Layout: 2/3 of the width is your side (battlefield + hand and piles); the other 1/3
// is a column always split into (at least) three opponent spaces — empty seats show
// an invite. Permanents are drawn MTG Arena-style (art crop,
// power/toughness); hovering shows the full card. Right-click the battlefield for
// table actions, a card for card actions.
//
// Parts with text inputs (chat, card search, custom card) are built once and never
// redrawn, so typing survives other players' updates.
const CARD_DRAG_TYPE = "text/kt-card"
const ZONE_LABELS = {
  battlefield: "Campo", hand: "Mão", library: "Grimório", stack: "Pilha", graveyard: "Cemitério", exile: "Exílio", command: "Comando"
}
// Battlefield rows (as % of its height) that double-click from hand fills in.
const BANDS = { creature: { top: 3, bottom: 31 }, other: { top: 36, bottom: 62 }, land: { top: 67, bottom: 95 } }
const CARD_COUNTERS = ["+1/+1", "-1/-1", "Lealdade", "Carga"]
const MIN_OPPONENT_SLOTS = 3
const LETHAL_COMMANDER_DAMAGE = 21
const MANA_COLORS = [["W", "Branco"], ["U", "Azul"], ["B", "Preto"], ["R", "Vermelho"], ["G", "Verde"], ["C", "Incolor"]]
// A permanent's height as % of its battlefield's height (board.css --kt-perm-h).
const PERM_HEIGHT = 12
const PLAYER_COUNTERS = ["Veneno", "Energia", "Experiência"]

export default class extends Controller {
  static targets = ["root", "decklistDialog", "flash"]
  static values = { tableSlug: String, seatId: String, seatToken: String, inviteUrl: String, format: String, decklistError: Boolean }

  connect() {
    this.view = null
    // The log starts closed and opens as a panel over the board, so it never takes
    // space from the battlefields.
    this.ui = { logOpen: false, viewer: null, menu: null, dismissedReveals: new Set() }
    this.dragging = false
    this.pendingRender = false
    this.hovered = null
    // Card instance ids picked with Ctrl (hover or click) for collective actions.
    this.selection = new Set()
    // Card <img> elements are reused across renders (keyed by instance + image) so
    // pictures don't blink black while they decode again.
    this.images = new Map()

    this.subscription = consumer.subscriptions.create(
      { channel: "TableChannel", table_slug: this.tableSlugValue, seat_id: this.seatIdValue, seat_token: this.seatTokenValue },
      { received: (data) => this.received(data), rejected: () => this.toast("Não foi possível entrar nesta mesa.") }
    )

    this.onKeydown = (event) => this.handleKey(event)
    this.onDocumentClick = (event) => { if (!event.target.closest(".kt-menu")) this.closeMenu() }
    // Renders wait while a card is being dragged (redrawing would drop the drag), so
    // the drag must always end — even when the dragged element's own dragend never
    // fires, e.g. because the drop already moved it.
    this.onDragFinished = () => setTimeout(() => this.endDrag(), 0)
    document.addEventListener("keydown", this.onKeydown)
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("dragend", this.onDragFinished, true)
    document.addEventListener("drop", this.onDragFinished, true)

    if (this.decklistErrorValue) this.openDecklist()
    this.flashTargets.forEach((el) => setTimeout(() => el.remove(), 3500))
  }

  disconnect() {
    this.subscription?.unsubscribe()
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("dragend", this.onDragFinished, true)
    document.removeEventListener("drop", this.onDragFinished, true)
  }

  // --- server traffic -------------------------------------------------------------

  received(data) {
    if (data.type === "error") return this.toast(data.message || data.error)
    if (data.type === "deck_tokens") { this.deckTokens = data.tokens; return }
    if (data.type !== "table_view") return

    const firstView = !this.view
    this.view = data
    if (firstView) {
      this.buildShell()
      if (!this.me.ready) this.openDecklist()
    }
    if (this.me.ready && this.decklistDialogTarget.open && !this.decklistErrorValue) this.decklistDialogTarget.close()
    this.refreshDeckTokens()
    this.requestRender()
  }

  perform(action, data = {}) { this.subscription.perform(action, data) }

  // The tokens your deck can make, for the "Adicionar token" menu — asked for again
  // whenever you're dealt a deck (submitting one, or a restart).
  refreshDeckTokens() {
    const dealt = [...this.view.log].reverse().find((e) => e.event_type === "restart" || (e.event_type === "start_game" && e.seat_id === this.seatIdValue))
    const key = dealt ? dealt.sequence : 0
    if (!this.me.ready || this.deckTokensKey === key) return
    this.deckTokensKey = key
    this.perform("deck_tokens")
  }

  move(instanceId, toZone, extra = {}) {
    this.perform("move_card", { card_instance_id: instanceId, to_zone: toZone, ...extra })
  }

  // --- derived view helpers -------------------------------------------------------

  get me() { return this.seat(this.seatIdValue) }
  get myTurn() { return this.view.active_seat_id === this.seatIdValue }
  // In turn order starting from whoever plays after you — the way they'd sit around
  // a real table.
  get opponents() {
    const seats = [...this.view.seats].sort((a, b) => a.seat_number - b.seat_number)
    const mine = seats.findIndex((s) => s.seat_id === this.seatIdValue)
    return [...seats.slice(mine + 1), ...seats.slice(0, mine)]
  }
  seat(seatId) { return this.view.seats.find((s) => s.seat_id === String(seatId)) }
  card(instance) { return instance.card_id ? this.view.cards[String(instance.card_id)] : null }

  // Where an instance currently is in this view: { seat, zone, instance }.
  locate(instanceId) {
    for (const seat of this.view.seats) {
      for (const [zone, cards] of Object.entries(seat.zones || {})) {
        const instance = cards.find((c) => c.id === instanceId)
        if (instance) return { seat, zone, instance }
      }
      const top = (seat.library_top || []).find((c) => c.id === instanceId)
      if (top) return { seat, zone: "library", instance: top }
    }
    for (const reveal of this.view.reveals) {
      const instance = reveal.cards.find((c) => c.id === instanceId)
      if (instance) return { seat: this.seat(reveal.owner_seat_id), zone: "revealed", instance }
    }
    return null
  }

  // The face currently up, as { name, type_line, power, toughness, loyalty, image, art }.
  face(instance) {
    if (instance.custom) return { ...instance.custom, image: null, art: null }
    const card = this.card(instance)
    if (!card) return null
    return card.faces[Math.min(instance.face_index || 0, card.faces.length - 1)]
  }

  // --- shell & rendering ----------------------------------------------------------

  buildShell() {
    this.el = {
      topbar: h("header", { class: "kt-topbar" }),
      play: h("div", { class: "kt-play" }),
      logList: h("ol", { class: "kt-log-list" }),
      overlays: h("div"),
      modals: h("div"),
      zoom: h("div", { class: "kt-zoom" })
    }
    const chatInput = h("input", { type: "text", placeholder: "Mensagem…", maxlength: 500 })
    const chat = h("form", { class: "kt-chat", onsubmit: (e) => {
      e.preventDefault()
      if (!chatInput.value.trim()) return
      this.perform("chat", { message: chatInput.value })
      chatInput.value = ""
    } }, chatInput)
    this.el.log = h("aside", { class: "kt-log" },
      h("header", { class: "kt-dialog-header" }, h("h3", {}, "Log da mesa"),
        h("button", { class: "kt-icon-btn", "aria-label": "Fechar log", onclick: () => this.toggleLog() }, "✕")),
      this.el.logList, chat)
    this.el.layout = h("div", { class: "kt-layout" }, this.el.topbar, this.el.play, this.el.log)

    this.rootTarget.className = "kt-root"
    this.rootTarget.replaceChildren(this.el.layout, this.el.overlays, this.el.modals, this.el.zoom)
  }

  requestRender() {
    if (this.dragging) this.pendingRender = true
    else this.render()
  }

  endDrag() {
    if (!this.dragging) return
    this.dragging = false
    if (this.pendingRender) this.render()
  }

  render() {
    if (!this.view) return
    this.pendingRender = false
    this.imagesUsed = new Set()
    const focus = this.captureFocus()
    for (const id of this.selection) if (!this.locate(id)) this.selection.delete(id)

    this.el.log.hidden = !this.ui.logOpen
    fill(this.el.topbar, this.renderTopBar())

    const opponents = this.opponents
    const slots = Math.max(MIN_OPPONENT_SLOTS, opponents.length)
    fill(this.el.play,
      this.me.ready ? this.renderMyArea() : this.renderNotReady(),
      h("section", { class: "kt-opponents", style: { "--kt-opponent-slots": slots } },
        opponents.map((s) => this.renderOpponent(s)),
        Array.from({ length: slots - opponents.length }, () => this.renderEmptySeat()))
    )

    const list = this.el.logList
    const atBottom = list.scrollHeight - list.scrollTop - list.clientHeight < 40
    fill(list, this.view.log.map((event) => h("li", { class: `kt-log-${event.event_type}` }, describeEvent(event, this.view))))
    if (atBottom) list.scrollTop = list.scrollHeight

    fill(this.el.overlays,
      this.renderReveals(),
      this.renderRestartVote(),
      this.renderViewer(),
      this.me.ready && !this.me.hand_kept ? this.renderOpeningHand() : null,
      this.ui.menu ? this.renderMenu() : null
    )
    for (const key of this.images.keys()) if (!this.imagesUsed.has(key)) this.images.delete(key)
    this.restoreFocus(focus)
  }

  // Inputs drawn by render() (marked data-focus-key) are rebuilt on every update; keep
  // whatever is being typed in one, and its caret, across the redraw.
  captureFocus() {
    const el = document.activeElement
    const key = el?.dataset?.focusKey
    if (!key || !this.rootTarget.contains(el)) return null
    let caret = null
    try { caret = [el.selectionStart, el.selectionEnd] } catch { caret = null }
    return { key, value: el.value, caret }
  }

  restoreFocus(focus) {
    if (!focus) return
    const el = this.rootTarget.querySelector(`[data-focus-key="${CSS.escape(focus.key)}"]`)
    if (!el) return
    el.value = focus.value
    el.focus()
    if (focus.caret && focus.caret[0] !== null) {
      try { el.setSelectionRange(...focus.caret) } catch { /* number inputs don't support carets */ }
    }
  }

  cardImage(instanceId, src, alt) {
    const key = `${instanceId}|${src}`
    let img = this.images.get(key)
    if (!img || this.imagesUsed.has(key)) {
      img = h("img", { src, alt, draggable: "false" })
      if (!this.imagesUsed.has(key)) this.images.set(key, img)
    }
    this.imagesUsed.add(key)
    return img
  }

  renderTopBar() {
    const me = this.me
    return [
      h("span", { class: "kt-brand" }, "Kitchentable"),
      me.ready ? this.renderLife(me) : null,
      me.ready ? this.renderCommanderDamage(me) : null,
      me.ready ? h("button", { class: "kt-link", onclick: (e) => this.openPlayerCounterMenu(e, me) }, "Contadores ▾") : null,
      me.ready ? this.renderCounterChips(me) : null,
      h("span", { class: "kt-turn", title: "Rodadas: voltas completas na mesa. Seu turno: quantos turnos você já começou." },
        `Rodada ${this.view.round}`, me.ready ? ` · Seu turno ${me.turns_taken}` : ""),
      this.renderTurnOrder(),
      me.ready ? this.renderTurnButton() : null,
      h("span", { class: "kt-spacer" }),
      me.ready ? h("span", { class: "kt-hint" }, "Botão direito no campo ou numa carta para ações") : null,
      me.ready ? h("button", { class: "kt-link", disabled: !!this.view.restart_vote, onclick: () => this.requestRestart() }, "Reiniciar") : null,
      h("button", { class: "kt-link", onclick: (e) => this.openDiceMenu(e) }, "Dados ▾"),
      h("button", { class: "kt-link", onclick: () => this.openDecklist() }, "Deck"),
      h("button", { class: "kt-link", onclick: () => this.toggleLog() }, this.ui.logOpen ? "Ocultar log" : "Log")
    ]
  }

  // "Iniciar turno" until you've started the turn you were passed (untap, draw), then
  // "Passar turno". Starting a turn when it isn't yours is allowed, after confirming.
  renderTurnButton() {
    if (this.myTurn && this.view.turn_started) {
      return h("button", { class: "kt-btn kt-btn-turn", title: "Passar o turno para o próximo jogador", onclick: () => this.perform("pass_turn") }, "Passar turno")
    }
    // Before the first player has started turn 1, nobody else can take a turn.
    const waitingForFirst = !this.myTurn && this.view.awaiting_first_turn
    const first = seatName(this.view, this.view.active_seat_id)
    return h("button", {
      class: `kt-btn kt-btn-turn ${this.myTurn ? "kt-glow" : "kt-btn-turn-idle"}`,
      disabled: waitingForFirst,
      title: this.myTurn ? "Desvirar, remover enjoo e comprar" : waitingForFirst ? `Aguardando ${first} começar a partida` : "Não é a sua vez",
      onclick: () => this.startTurn()
    }, "Iniciar turno", h("kbd", {}, "N"))
  }

  // The turn button, and the N key.
  startTurn() {
    if (this.myTurn && this.view.turn_started) return this.toast("Seu turno já começou — passe o turno quando terminar.", "info")
    if (this.myTurn) return this.perform("start_turn")
    if (this.view.awaiting_first_turn) return
    if (window.confirm("Tem certeza que deseja jogar outro turno mesmo que não seja sua vez?")) this.perform("start_turn", { out_of_turn: true })
  }

  // Seats in turn order (seat numbers), whoever plays now highlighted, you marked.
  renderTurnOrder() {
    const seats = [...this.view.seats].filter((s) => s.ready).sort((a, b) => a.seat_number - b.seat_number)
    if (seats.length < 2) return null
    return h("span", { class: "kt-turn-order", title: "Ordem dos turnos" }, seats.flatMap((seat, i) => [
      i ? h("span", { class: "kt-turn-arrow" }, "→") : null,
      h("span", { class: ["kt-turn-seat", seat.seat_id === this.view.active_seat_id && "kt-turn-active", seat.seat_id === this.seatIdValue && "kt-turn-me"].filter(Boolean).join(" ") },
        h("small", {}, seat.seat_number), seat.seat_id === this.seatIdValue ? "Você" : seat.display_name)
    ]))
  }

  renderLife(seat) {
    const target = seat.seat_id === this.seatIdValue ? {} : { target_seat_id: seat.seat_id }
    return h("span", { class: "kt-life" },
      h("button", { class: "kt-life-btn", title: "-1 (Shift: -5)", onclick: (e) => this.perform("set_life", { delta: e.shiftKey ? -5 : -1, ...target }) }, "−"),
      h("span", { class: "kt-life-total" }, seat.life_total),
      h("button", { class: "kt-life-btn", title: "+1 (Shift: +5)", onclick: (e) => this.perform("set_life", { delta: e.shiftKey ? 5 : 1, ...target }) }, "+"))
  }

  // Damage this player has taken from each commander that isn't theirs, always on
  // screen. Raising it takes the same amount of life (the server does that); 21 from
  // one commander is lethal.
  renderCommanderDamage(seat) {
    const commanders = (this.view.commanders || []).filter((c) => c.owner_seat_id !== seat.seat_id)
    if (!commanders.length) return null
    const target = seat.seat_id === this.seatIdValue ? {} : { target_seat_id: seat.seat_id }
    const change = (commander, delta) => this.perform("commander_damage", { commander_instance_id: commander.instance_id, delta, ...target })

    return h("span", { class: "kt-cmd-damage" }, commanders.map((commander) => {
      const name = this.view.cards[String(commander.card_id)]?.name || "?"
      const owner = this.seat(commander.owner_seat_id)?.display_name
      const value = seat.commander_damage?.[commander.instance_id] || 0
      return h("span", {
        class: `kt-cmd-chip ${value >= LETHAL_COMMANDER_DAMAGE ? "kt-lethal" : value >= LETHAL_COMMANDER_DAMAGE - 5 ? "kt-near-lethal" : ""}`,
        title: `Dano de comandante de ${name} (${owner}) — letal com ${LETHAL_COMMANDER_DAMAGE}. Somar tira vida.`
      },
        h("span", { class: "kt-cmd-name" }, shortName(name)),
        this.stepper(`cmd|${seat.seat_id}|${commander.instance_id}`, value, (delta) => change(commander, delta)))
    }))
  }

  // − [total] +: buttons step by 1 (Shift: 5); typing a total and pressing Enter (or
  // leaving the field) sends the difference. Escape puts the current total back.
  stepper(focusKey, value, onDelta) {
    return [
      h("button", { class: "kt-cmd-btn", title: "−1 (Shift: −5)", onclick: (e) => onDelta(e.shiftKey ? -5 : -1) }, "−"),
      this.totalInput(focusKey, value, onDelta),
      h("button", { class: "kt-cmd-btn", title: "+1 (Shift: +5)", onclick: (e) => onDelta(e.shiftKey ? 5 : 1) }, "+")
    ]
  }

  totalInput(focusKey, value, onDelta) {
    const input = h("input", {
      type: "number", min: 0, max: 999, value, class: "kt-cmd-input",
      dataset: { focusKey }, title: "Digite o total e tecle Enter"
    })
    // Enter commits and blurs, and the blur fires "change" too — track what was
    // already applied so the difference is only sent once.
    // An input replaced by a redraw while focused also fires "change" as it leaves the
    // page; only the one on screen may commit.
    let applied = value
    const commit = () => {
      if (!input.isConnected) return
      const total = parseInt(input.value, 10)
      if (!Number.isFinite(total) || total < 0) { input.value = applied; return }
      if (total !== applied) onDelta(total - applied)
      applied = total
    }
    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter") { event.preventDefault(); commit(); input.blur() }
      if (event.key === "Escape") { input.value = value; input.blur() }
    })
    input.addEventListener("change", commit)
    input.addEventListener("focus", () => input.select())
    return input
  }

  // Player counters (poison, energy...) appear once added from the counters menu,
  // with the same − [total] + controls as commander damage.
  renderCounterChips(seat) {
    const entries = Object.entries(seat.counters || {})
    if (!entries.length) return null
    const target = seat.seat_id === this.seatIdValue ? {} : { target_seat_id: seat.seat_id }
    return h("span", { class: "kt-cmd-damage" }, entries.map(([key, value]) => h("span", {
      class: `kt-cmd-chip kt-counter-chip ${key === "Veneno" && value >= 10 ? "kt-lethal" : ""}`, title: key
    },
      h("span", { class: "kt-cmd-name" }, key),
      this.stepper(`counter|${seat.seat_id}|${key}`, value, (delta) => this.perform("player_counter", { key, delta, ...target })))))
  }

  renderNotReady() {
    return h("section", { class: "kt-empty" },
      h("p", {}, "Você ainda não enviou um deck para esta mesa."),
      h("button", { class: "kt-btn kt-btn-primary", onclick: () => this.openDecklist() }, "Enviar deck"))
  }

  renderMyArea() {
    const me = this.me
    return h("section", { class: "kt-mine" },
      h("div", { class: "kt-field-wrap" },
        this.renderBattlefield(me, { own: true }),
        this.renderStack()),
      h("div", { class: "kt-tray" },
        this.renderHand(me),
        this.renderLibrary(me),
        h("div", { class: "kt-zones" },
          this.renderZoneTile(me, "command"),
          this.renderZoneTile(me, "graveyard"),
          this.renderZoneTile(me, "exile")),
        this.renderManaPool(me)))
  }

  // Cards sit where they were dropped (x/y as % of the area); cards without a spot yet
  // flow into their type's row.
  renderBattlefield(seat, { own = false } = {}) {
    const field = h("div", { class: `kt-battlefield ${own ? "kt-battlefield-own" : ""}` },
      h("div", { class: "kt-band-guides" }, h("span", {}, "Criaturas"), h("span", {}, "Outras permanentes"), h("span", {}, "Terrenos")))

    this.makeDropTarget(field, (ids, event) => {
      const at = this.fieldPoint(field, event, this.dragOffset)
      if (ids.length === 1) return this.move(ids[0], "battlefield", { to_seat_id: seat.seat_id, ...at })
      // Several cards: side by side from the drop point, wrapping to a new row.
      const width = PERM_HEIGHT * 1.5 * (field.clientHeight / field.clientWidth) + 0.8
      const perRow = Math.max(1, Math.floor((94 - at.x) / width) + 1)
      this.moveMany(ids, "battlefield", {
        to_seat_id: seat.seat_id,
        positions: ids.map((_, i) => ({ x: round(at.x + (i % perRow) * width), y: round(Math.min(88, at.y + Math.floor(i / perRow) * (PERM_HEIGHT + 1))) }))
      })
    })
    field.addEventListener("click", (event) => {
      if (!event.target.closest(".kt-perm") && !event.ctrlKey) this.clearSelection()
    })
    if (own) {
      field.addEventListener("contextmenu", (event) => {
        if (event.target.closest(".kt-perm")) return
        event.preventDefault()
        this.openFieldMenu(event, this.fieldPoint(field, event))
      })
    }

    const unplaced = { creature: 0, other: 0, land: 0 }
    for (const instance of seat.zones.battlefield) {
      let { x, y } = instance
      if (x === null || y === null) {
        const band = this.bandOf(instance)
        x = 1 + (unplaced[band] % 8) * 12
        y = BANDS[band].top + Math.floor(unplaced[band]++ / 8) * (PERM_HEIGHT + 1)
      }
      const el = this.renderPermanent(instance, seat)
      el.style.left = `${x}%`
      el.style.top = `${y}%`
      if (own) {
        el.addEventListener("click", (event) => {
          if (event.detail > 1 || event.ctrlKey) return
          this.perform("tap_card", { card_instance_id: instance.id, tapped: !instance.tapped })
        })
      }
      field.append(el)
    }
    return field
  }

  // Pointer position in the field as % of its size (minus where the card was grabbed).
  fieldPoint(field, event, offset = { x: 0, y: 0 }) {
    const rect = field.getBoundingClientRect()
    return {
      x: round(clamp(((event.clientX - rect.left - offset.x) / rect.width) * 100, 0, 94)),
      y: round(clamp(((event.clientY - rect.top - offset.y) / rect.height) * 100, 0, 90))
    }
  }

  bandOf(instance) {
    const type = this.face(instance)?.type_line || ""
    if (/\bLand\b/.test(type)) return "land"
    if (/\bCreature\b/.test(type)) return "creature"
    return "other"
  }

  // Next free spot at the end of a type's row in your battlefield, wrapping down.
  // Permanents are sized by the field's height, so their width as a % of the
  // field's width depends on its shape.
  nextSpot(band) {
    const field = this.el.play.querySelector(".kt-battlefield-own")
    const aspect = field && field.clientWidth ? field.clientHeight / field.clientWidth : 0.66
    const width = PERM_HEIGHT * 1.5 * aspect + 0.8
    const { top, bottom } = BANDS[band]
    const inBand = this.me.zones.battlefield.filter((i) => i.y !== null && i.y >= top - 2 && i.y < bottom)
    for (let row = top; row <= bottom - PERM_HEIGHT; row += PERM_HEIGHT + 1) {
      const rowCards = inBand.filter((i) => Math.abs(i.y - row) < 4)
      const x = rowCards.length ? Math.max(...rowCards.map((i) => i.x)) + width : 1
      if (x <= 100 - width) return { x: round(x), y: row }
    }
    return { x: round(1 + Math.random() * 60), y: top }
  }

  // Double-click from hand: lands to the bottom row, creatures to the top, other
  // permanents in the middle; instants and sorceries go on the stack to resolve.
  playFromHand(instance) {
    const type = this.face(instance)?.type_line || ""
    if (/\b(Instant|Sorcery)\b/.test(type)) return this.move(instance.id, "stack")
    this.move(instance.id, "battlefield", this.nextSpot(this.bandOf(instance)))
  }

  // Arena-style permanent: art crop, power/toughness or loyalty, counters.
  renderPermanent(instance, seat) {
    const face = this.face(instance)
    const hidden = instance.face_down || !face
    const counters = Object.entries(instance.counters || {}).filter(([k]) => !["+1/+1", "-1/-1", "Lealdade"].includes(k))
    const pt = !hidden && powerToughness(instance, face)
    const loyalty = !hidden && (instance.counters?.Lealdade ?? face.loyalty)

    const el = h("div", {
      class: ["kt-perm", instance.tapped && "kt-tapped", hidden && "kt-facedown", this.selection.has(instance.id) && "kt-selected"].filter(Boolean).join(" "),
      draggable: "true", dataset: { id: instance.id }, title: hidden ? "Carta virada para baixo" : face.name
    },
      hidden ? h("div", { class: "kt-card-back" })
        : face.art ? this.cardImage(instance.id, face.art, face.name)
        : h("div", { class: "kt-perm-text" }, face.name),
      !hidden ? h("span", { class: "kt-perm-name" }, face.name) : null,
      pt ? h("span", { class: `kt-pt ${pt.modified ? "kt-pt-modified" : ""}` }, pt.text) : null,
      loyalty ? h("span", { class: "kt-loyalty" }, loyalty) : null,
      counters.length ? h("div", { class: "kt-counters" }, counters.map(([k, v]) => h("span", { title: k }, `${shortCounter(k)} ${v}`))) : null,
      instance.token ? h("span", { class: "kt-badge" }, "token") : null,
      instance.sick && !hidden ? h("button", {
        class: "kt-sick", title: "Enjoo de invocação — clique para remover",
        onclick: (e) => { e.stopPropagation(); this.perform("remove_sickness", { card_instance_id: instance.id }) }
      }, "Zz") : null)
    this.wireCard(el, instance, "battlefield", seat)
    return el
  }

  // Full card, for hand, piles, viewers and the stack.
  renderCard(instance, { zone, seat }) {
    const face = this.face(instance)
    const hidden = instance.face_down || !face
    const counters = Object.entries(instance.counters || {})

    const el = h("div", {
      class: ["kt-card", instance.tapped && "kt-tapped", this.selection.has(instance.id) && "kt-selected"].filter(Boolean).join(" "),
      draggable: "true", dataset: { id: instance.id }, title: hidden ? "Carta virada para baixo" : face.name
    },
      hidden ? h("div", { class: "kt-card-back" })
        : face.image ? this.cardImage(instance.id, face.image, face.name)
        : h("div", { class: "kt-card-text" }, face.name, h("small", {}, face.type_line || ""),
            face.power ? h("strong", {}, `${face.power}/${face.toughness}`) : null),
      counters.length ? h("div", { class: "kt-counters" }, counters.map(([k, v]) => h("span", { title: k }, `${shortCounter(k)} ${v}`))) : null,
      instance.token ? h("span", { class: "kt-badge" }, "token") : null)
    this.wireCard(el, instance, zone, seat)
    return el
  }

  // Ctrl + hover (or Ctrl + click) selects; dragging or right-clicking a selected card
  // acts on the whole selection.
  wireCard(el, instance, zone, seat) {
    el.addEventListener("dragstart", (event) => {
      this.dragging = true
      const rect = el.getBoundingClientRect()
      this.dragOffset = { x: event.clientX - rect.left, y: event.clientY - rect.top }
      const ids = this.selection.has(instance.id) && this.selection.size > 1 ? [...this.selection] : [instance.id]
      event.dataTransfer.setData(CARD_DRAG_TYPE, JSON.stringify(ids))
      event.dataTransfer.effectAllowed = "move"
      this.hideZoom()
    })
    el.addEventListener("contextmenu", (event) => {
      event.preventDefault()
      event.stopPropagation()
      if (this.selection.size > 1 && this.selection.has(instance.id)) this.openSelectionMenu(event)
      else this.openCardMenu(event, instance, zone, seat)
    })
    // Moving onto a card with Ctrl held already selects it, so a Ctrl+click right after
    // must not toggle it back off.
    el.addEventListener("click", (event) => {
      if (!event.ctrlKey) return
      event.preventDefault()
      event.stopPropagation()
      if (this.selectedByHover === instance.id) this.selectedByHover = null
      else this.toggleSelected(instance.id)
    }, true)
    el.addEventListener("mouseenter", (event) => {
      this.hovered = { instance, zone, seat }
      if (event.ctrlKey && !this.selection.has(instance.id)) {
        this.select(instance.id)
        this.selectedByHover = instance.id
      }
      this.showZoom(instance)
    })
    el.addEventListener("mouseleave", () => { this.hovered = null; this.selectedByHover = null; this.hideZoom() })
  }

  renderHand(seat) {
    const hand = h("div", { class: "kt-hand" },
      h("span", { class: "kt-zone-label" }, `Mão (${seat.zones.hand.length}) · clique duplo para jogar`),
      h("div", { class: "kt-hand-cards" }, seat.zones.hand.map((instance) => {
        const el = this.renderCard(instance, { zone: "hand", seat })
        el.addEventListener("dblclick", () => this.playFromHand(instance))
        return h("div", { class: "kt-hand-slot" }, el)
      })))
    this.makeDropTarget(hand, this.dropTo("hand"))
    return hand
  }

  // Manual mana tracker: click a color to add, right-click to spend. Not tied to
  // tapping lands — players keep it themselves.
  renderManaPool(seat) {
    const pool = seat.mana_pool || {}
    const total = Object.values(pool).reduce((a, b) => a + b, 0)
    return h("div", { class: "kt-mana", title: "Mana flutuando — clique soma, botão direito gasta" },
      h("div", { class: "kt-mana-head" }, h("span", {}, "Mana"), h("b", {}, total),
        h("button", { class: "kt-link kt-mana-clear", disabled: !total, onclick: () => this.perform("mana", { clear: true }) }, "Limpar")),
      h("div", { class: "kt-mana-grid" }, MANA_COLORS.map(([color, label]) => h("button", {
        class: `kt-mana-pip kt-mana-${color} ${pool[color] ? "" : "kt-mana-empty"}`, title: label,
        onclick: () => this.perform("mana", { color, delta: 1 }),
        oncontextmenu: (e) => { e.preventDefault(); this.perform("mana", { color, delta: -1 }) }
      }, h("span", { class: "kt-mana-symbol" }, color), h("span", { class: "kt-mana-count" }, pool[color] || 0)))))
  }

  // Command zone, graveyard, exile: stacked rows at the right edge, each a small
  // top-card thumbnail with name and count, so the hand keeps the width. Click opens the zone to inspect every card; cards can
  // still be dropped on the tile (or dragged off its top card).
  renderZoneTile(seat, zoneName) {
    const cards = seat.zones[zoneName]
    const tile = h("div", { class: "kt-pile", title: `${ZONE_LABELS[zoneName]} — clique para ver as cartas`,
                            onclick: () => this.openViewer({ seatId: seat.seat_id, zone: zoneName }) },
      cards[0] ? this.renderCard(cards[0], { zone: zoneName, seat }) : h("div", { class: "kt-card kt-card-slot" }),
      h("span", { class: "kt-pile-label" }, ZONE_LABELS[zoneName], h("b", {}, cards.length)))
    this.makeDropTarget(tile, this.dropTo(zoneName))
    return tile
  }

  // Full-size, next to the hand. Click draws; right-click opens its actions (search,
  // look at the top, mill...).
  renderLibrary(seat) {
    const count = seat.zone_counts.library
    const pile = h("div", { class: "kt-library", title: "Grimório — clique para comprar · botão direito para opções · solte uma carta aqui para o topo (Shift: fundo)",
                            onclick: () => this.perform("draw"),
                            oncontextmenu: (e) => { e.preventDefault(); this.openMenu(e, this.libraryItems(seat)) } },
      h("span", { class: "kt-zone-label" }, `Grimório (${count})`, seat.top_revealed ? " · topo revelado" : ""),
      seat.library_top_card ? this.renderCard(seat.library_top_card, { zone: "library", seat })
        : count ? h("div", { class: "kt-card kt-card-back-wrap" }, h("div", { class: "kt-card-back" })) : h("div", { class: "kt-card kt-card-slot" }))
    this.makeDropTarget(pile, this.dropTo("library", (event) => ({ to_position: event.shiftKey ? -1 : 0 })))
    return pile
  }

  // Spells being cast — everyone's — in the middle of your battlefield. Yours get
  // resolve buttons.
  renderStack() {
    const spells = this.view.seats.flatMap((seat) => (seat.zones?.stack || []).map((instance) => ({ seat, instance })))
    if (!spells.length) return null
    return h("div", { class: "kt-stack" }, spells.map(({ seat, instance }) => {
      const mine = seat.seat_id === this.seatIdValue
      return h("div", { class: "kt-spell" },
        h("small", {}, mine ? "Você está conjurando" : `${seat.display_name} está conjurando`),
        this.renderCard(instance, { zone: "stack", seat }),
        mine ? h("div", { class: "kt-spell-actions" },
          h("button", { class: "kt-btn kt-btn-small kt-btn-primary", onclick: () => this.move(instance.id, "graveyard") }, "Resolver → cemitério"),
          h("button", { class: "kt-btn kt-btn-small", onclick: () => this.move(instance.id, "exile") }, "→ exílio"),
          h("button", { class: "kt-btn kt-btn-small", onclick: () => this.move(instance.id, "hand") }, "Voltar à mão")) : null)
    }))
  }

  renderOpponent(seat) {
    const active = this.view.active_seat_id === seat.seat_id
    if (!seat.ready) {
      return h("article", { class: "kt-opponent kt-opponent-waiting" },
        h("header", {}, h("span", { class: "kt-seat-number" }, seat.seat_number), h("strong", {}, seat.display_name)),
        h("p", { class: "kt-muted" }, "escolhendo o deck…"))
    }
    return h("article", { class: `kt-opponent ${active ? "kt-active" : ""}` },
      h("header", {},
        h("span", { class: "kt-seat-number", title: "Assento / ordem de turno" }, seat.seat_number),
        h("strong", {}, seat.display_name),
        active ? h("span", { class: "kt-chip kt-chip-turn" }, "na vez") : null,
        h("span", { class: "kt-count", title: "Turnos que este jogador já começou" }, `turno ${seat.turns_taken}`),
        this.renderLife(seat),
        this.renderCommanderDamage(seat),
        h("button", { class: "kt-link", title: "Contadores", onclick: (e) => this.openPlayerCounterMenu(e, seat) }, "±"),
        this.renderCounterChips(seat),
        seat.mulligan_count && !seat.hand_kept ? h("span", { class: "kt-chip" }, `mulligan ${seat.mulligan_count}`) : null,
        !seat.hand_kept ? h("span", { class: "kt-chip" }, "decidindo a mão") : null,
        seat.peek ? h("span", { class: "kt-chip kt-chip-warn" }, `olhando ${seat.peek.count} de ${seatName(this.view, seat.peek.seat_id)}`) : null),
      h("div", { class: "kt-opponent-body" },
        seat.zones.command.length
          ? h("div", { class: "kt-opponent-command" }, seat.zones.command.map((i) => this.renderCard(i, { zone: "command", seat })))
          : null,
        this.renderBattlefield(seat)),
      h("footer", { class: "kt-opponent-zones" },
        h("span", { title: "Cartas na mão" }, `Mão ${seat.zone_counts.hand}`),
        h("button", { class: "kt-link", title: "Olhar o topo do grimório", onclick: () => this.promptPeek(seat) }, `Grimório ${seat.zone_counts.library}`),
        seat.library_top_card ? h("span", { class: "kt-revealed-top", title: "Topo revelado" }, this.renderCard(seat.library_top_card, { zone: "library", seat })) : null,
        h("button", { class: "kt-link", onclick: () => this.openViewer({ seatId: seat.seat_id, zone: "graveyard" }) }, `Cemitério ${seat.zone_counts.graveyard}`),
        h("button", { class: "kt-link", onclick: () => this.openViewer({ seatId: seat.seat_id, zone: "exile" }) }, `Exílio ${seat.zone_counts.exile}`)))
  }

  renderEmptySeat() {
    return h("article", { class: "kt-opponent kt-opponent-empty" },
      h("p", {}, "Lugar livre"),
      h("button", { class: "kt-btn kt-btn-small", onclick: () => this.copyInvite() }, "Copiar link de convite"))
  }

  // The bare table link — never this page's URL, which carries your seat token.
  async copyInvite() {
    try {
      await navigator.clipboard.writeText(this.inviteUrlValue)
      this.toast("Link da mesa copiado — quem abrir entra num lugar livre.", "info")
    } catch {
      window.prompt("Copie o link da mesa:", this.inviteUrlValue)
    }
  }

  // onDrop(ids, event): a drag carries one card, or every selected card.
  makeDropTarget(el, onDrop) {
    el.addEventListener("dragover", (event) => {
      if (!event.dataTransfer.types.includes(CARD_DRAG_TYPE)) return
      event.preventDefault()
      event.stopPropagation()
      el.classList.add("kt-drop-hover")
    })
    el.addEventListener("dragleave", () => el.classList.remove("kt-drop-hover"))
    el.addEventListener("drop", (event) => {
      const data = event.dataTransfer.getData(CARD_DRAG_TYPE)
      el.classList.remove("kt-drop-hover")
      if (!data) return
      event.preventDefault()
      event.stopPropagation()
      onDrop(JSON.parse(data), event)
    })
  }

  // Drop handler for a zone: one card is a plain move, several a batch move.
  dropTo(zone, extra = () => ({})) {
    return (ids, event) => (ids.length === 1 ? this.move(ids[0], zone, extra(event)) : this.moveMany(ids, zone, extra(event)))
  }

  // One update for many cards; `positions` ([{ x, y }] per card) only for the battlefield.
  moveMany(ids, toZone, { positions, ...extra } = {}) {
    this.perform("move_cards", {
      to_zone: toZone, ...extra,
      moves: ids.map((id, i) => ({ card_instance_id: id, ...(positions ? positions[i] : {}) }))
    })
    this.clearSelection()
  }

  // --- selection --------------------------------------------------------------------

  select(id) {
    if (this.selection.has(id)) return
    this.selection.add(id)
    this.markSelection()
  }

  toggleSelected(id) {
    if (this.selection.has(id)) this.selection.delete(id)
    else this.selection.add(id)
    this.markSelection()
  }

  clearSelection() {
    if (!this.selection.size) return
    this.selection.clear()
    this.markSelection()
  }

  // Selection changes only restyle cards; no full redraw needed.
  markSelection() {
    this.rootTarget.querySelectorAll("[data-id]").forEach((el) => el.classList.toggle("kt-selected", this.selection.has(el.dataset.id)))
  }

  // --- overlays -------------------------------------------------------------------

  // Archidekt-style opening hand: keep or mulligan, with drop spots for the cards a
  // London mulligan puts on the bottom (or Serum Powder-style exiles).
  renderOpeningHand() {
    const me = this.me
    const bottom = h("div", { class: "kt-dropzone" }, "Fundo do grimório")
    this.makeDropTarget(bottom, this.dropTo("library", () => ({ to_position: -1 })))
    const exile = h("div", { class: "kt-dropzone" }, "Exílio")
    this.makeDropTarget(exile, this.dropTo("exile"))

    return h("div", { class: "kt-overlay" },
      h("div", { class: "kt-opening" },
        h("h2", {}, "Mão inicial"),
        h("div", { class: "kt-opening-buttons" },
          h("button", { class: "kt-btn kt-btn-keep", onclick: () => this.perform("keep_hand") }, "Manter"),
          h("button", { class: "kt-btn", onclick: () => this.perform("mulligan") }, `Mulligan (${me.mulligan_count})`)),
        me.mulligan_count ? h("p", { class: "kt-muted" }, `Mulligan londrino: arraste ${me.mulligan_count} carta(s) para o fundo do grimório.`) : null,
        h("div", { class: "kt-fan" }, me.zones.hand.map((instance, i, all) => {
          const el = this.renderCard(instance, { zone: "hand", seat: me })
          const offset = i - (all.length - 1) / 2
          el.style.setProperty("--fan-rotate", `${offset * 5}deg`)
          el.style.setProperty("--fan-drop", `${offset * offset * 4}px`)
          return el
        })),
        h("div", { class: "kt-dropzones" }, bottom, exile)))
  }

  // Everyone dealt in must accept a restart: a pop-up for whoever hasn't answered, a
  // waiting banner for whoever has (the requester can call it off).
  renderRestartVote() {
    const vote = this.view.restart_vote
    if (!vote || !this.me.ready) return null
    const name = (id) => (id === this.seatIdValue ? "você" : seatName(this.view, id))
    const requester = name(vote.requested_by)

    if (vote.pending.includes(this.seatIdValue)) {
      return h("div", { class: "kt-overlay kt-vote-overlay" },
        h("div", { class: "kt-viewer kt-vote" },
          h("h2", {}, `${requester} quer reiniciar o jogo`),
          h("p", {}, "Todos voltam ao começo: grimório embaralhado, mão nova de 7 e vida inicial. O primeiro jogador será sorteado."),
          h("p", { class: "kt-muted" }, `Já aceitaram: ${vote.accepted.map(name).join(", ")}`),
          h("div", { class: "kt-vote-buttons" },
            h("button", { class: "kt-btn kt-btn-keep", onclick: () => this.perform("restart_vote", { answer: "accept" }) }, "Aceitar"),
            h("button", { class: "kt-btn", onclick: () => this.perform("restart_vote", { answer: "decline" }) }, "Recusar"))))
    }
    return h("div", { class: "kt-vote-banner" },
      h("span", {}, `Reinício pedido por ${requester} — aguardando ${vote.pending.map(name).join(", ")}`),
      vote.requested_by === this.seatIdValue
        ? h("button", { class: "kt-link", onclick: () => this.perform("restart_vote", { answer: "decline" }) }, "Cancelar")
        : null)
  }

  requestRestart() {
    if (window.confirm("Pedir para reiniciar o jogo? Todos os jogadores precisam aceitar.")) this.perform("restart_vote", { answer: "request" })
  }

  renderReveals() {
    const reveals = this.view.reveals.filter((r) => !this.ui.dismissedReveals.has(r.id))
    if (!reveals.length) return null
    return h("div", { class: "kt-reveals" }, reveals.map((reveal) => {
      const mine = reveal.by_seat_id === this.seatIdValue
      return h("div", { class: "kt-reveal" },
        h("header", {},
          h("strong", {}, `${seatName(this.view, reveal.by_seat_id)} revelou`),
          mine
            ? h("button", { class: "kt-link", onclick: () => this.perform("end_reveal", { reveal_id: reveal.id }) }, "Encerrar")
            : h("button", { class: "kt-link", onclick: () => { this.ui.dismissedReveals.add(reveal.id); this.render() } }, "Ocultar")),
        h("div", { class: "kt-reveal-cards" }, reveal.cards.map((i) => this.renderCard(i, { zone: "revealed", seat: this.seat(reveal.owner_seat_id) }))))
    }))
  }

  // Pile browser (graveyard/exile of anyone), or the library top you're peeking at.
  renderViewer() {
    const peekSeat = this.me.peek && this.seat(this.me.peek.seat_id)
    if (peekSeat?.library_top) return this.renderPeekViewer(peekSeat)

    const viewer = this.ui.viewer
    if (!viewer) return null
    const seat = this.seat(viewer.seatId)
    const cards = seat?.zones?.[viewer.zone] || []
    const castable = viewer.zone === "command" && seat.seat_id === this.seatIdValue
    return this.viewerShell(`${ZONE_LABELS[viewer.zone]} de ${seat.display_name} (${cards.length})`,
      () => { this.ui.viewer = null; this.render() },
      cards.map((instance) => {
        const el = this.renderCard(instance, { zone: viewer.zone, seat })
        if (castable) el.addEventListener("dblclick", () => { this.ui.viewer = null; this.playFromHand(instance) })
        return el
      }))
  }

  // Cards revealed from a library (yours or another player's): a fixed set — each card
  // leaves it once moved (even back on top), nothing new slides in. Drop them on a
  // zone, double-click to take one to hand, or send the rest to the top/bottom in a
  // random order.
  renderPeekViewer(seat) {
    if (this.me.peek.search) return this.renderSearchViewer(seat)
    const own = seat.seat_id === this.seatIdValue
    const cards = seat.library_top
    const zone = (label, toZone, extra) => {
      const el = h("div", { class: "kt-dropzone kt-dropzone-small" }, label)
      this.makeDropTarget(el, this.dropTo(toZone, () => extra || {}))
      return el
    }

    return this.viewerShell(
      `Cartas reveladas do grimório${own ? "" : ` de ${seat.display_name}`} (${cards.length})`,
      () => this.perform("stop_peek"),
      cards.map((instance, index) => {
        const el = this.renderCard(instance, { zone: "library", seat })
        el.addEventListener("dblclick", () => this.move(instance.id, "hand"))
        return h("div", { class: "kt-peek-slot" }, h("small", {}, `#${index + 1}`), el)
      }),
      [
        h("div", { class: "kt-dropzones-row" },
          zone("Mão", "hand"), zone("Campo", "battlefield"), zone("Cemitério", "graveyard"), zone("Exílio", "exile"),
          zone("Topo do grimório", "library", { to_position: 0 }), zone("Fundo do grimório", "library", { to_position: -1 })),
        h("div", { class: "kt-viewer-actions" },
          h("button", { class: "kt-btn", disabled: !cards.length, onclick: () => this.perform("peek_remaining", { placement: "top" }) }, "Restantes no topo (aleatório)"),
          h("button", { class: "kt-btn", disabled: !cards.length, onclick: () => this.perform("peek_remaining", { placement: "bottom" }) }, "Restantes no fundo (aleatório)"),
          own && cards.length ? h("button", { class: "kt-btn", onclick: () => this.revealIds(cards.map((c) => c.id)) }, "Revelar para a mesa") : null,
          h("button", { class: "kt-btn kt-btn-primary", onclick: () => this.perform("stop_peek") }, "Fechar"))
      ],
      "Arraste para uma zona, clique duplo para a mão, ou use o botão direito. Fechar deixa as restantes onde estão.")
  }

  // Searching your whole library: filter by name, take what you need (drag, double-
  // click to hand, or right-click), then close — shuffling or not.
  renderSearchViewer(seat) {
    const filter = (this.ui.searchFilter || "").trim().toLowerCase()
    const cards = seat.library_top.filter((i) => !filter || (this.face(i)?.name || "").toLowerCase().includes(filter))
    const input = h("input", { type: "search", class: "kt-input kt-search-filter", placeholder: "Filtrar por nome…", value: this.ui.searchFilter || "",
                               dataset: { focusKey: "library-search" } })
    input.addEventListener("input", () => { this.ui.searchFilter = input.value; this.render() })
    const close = (shuffle) => {
      this.ui.searchFilter = ""
      if (shuffle) this.perform("shuffle")
      this.perform("stop_peek")
    }

    return h("div", { class: "kt-overlay", onclick: (e) => { if (e.target === e.currentTarget) close(false) } },
      h("div", { class: "kt-viewer kt-search-viewer" },
        h("header", { class: "kt-dialog-header" }, h("h2", {}, `Buscar no grimório (${seat.library_top.length})`),
          h("button", { class: "kt-icon-btn", title: "Fechar", onclick: () => close(false) }, "✕")),
        input,
        h("p", { class: "kt-muted" }, "Clique duplo manda a carta para a mão; arraste ou use o botão direito para outras zonas."),
        h("div", { class: "kt-viewer-cards" }, cards.length ? cards.map((instance) => {
          const el = this.renderCard(instance, { zone: "library", seat })
          el.addEventListener("dblclick", () => this.move(instance.id, "hand"))
          return el
        }) : h("p", { class: "kt-muted" }, "Nenhuma carta.")),
        h("footer", {},
          h("button", { class: "kt-btn", onclick: () => close(false) }, "Fechar"),
          h("button", { class: "kt-btn kt-btn-primary", onclick: () => close(true) }, "Fechar e embaralhar"))))
  }

  viewerShell(title, onClose, cards, footer = [], hint = "Arraste as cartas para onde quiser, ou use o botão direito.") {
    return h("div", { class: "kt-overlay", onclick: (e) => { if (e.target === e.currentTarget) onClose() } },
      h("div", { class: "kt-viewer" },
        h("header", { class: "kt-dialog-header" }, h("h2", {}, title), h("button", { class: "kt-icon-btn", title: "Fechar", onclick: onClose }, "✕")),
        h("p", { class: "kt-muted" }, hint),
        h("div", { class: "kt-viewer-cards" }, cards.length ? cards : h("p", { class: "kt-muted" }, "Vazio.")),
        footer.length ? h("footer", {}, footer) : null))
  }

  // --- menus ----------------------------------------------------------------------

  // Items: { label, run, key, children }, "-" for a separator, { heading }; falsy
  // entries are skipped so menus can be built with conditions inline.
  renderMenu() {
    const { x, y, items } = this.ui.menu
    const flip = x > window.innerWidth - 460
    const menu = h("div", { class: `kt-menu ${flip ? "kt-menu-flip" : ""}`, style: { left: `${x}px`, top: `${y}px` } }, this.menuItems(items))
    requestAnimationFrame(() => {
      const rect = menu.getBoundingClientRect()
      if (rect.bottom > window.innerHeight) menu.style.top = `${Math.max(8, window.innerHeight - rect.height - 8)}px`
      if (rect.right > window.innerWidth) menu.style.left = `${Math.max(8, window.innerWidth - rect.width - 8)}px`
    })
    return menu
  }

  menuItems(items) {
    return items.filter(Boolean).map((item) => {
      if (item === "-") return h("hr")
      if (item.heading) return h("div", { class: "kt-menu-heading" }, item.heading)
      if (item.children) {
        return h("div", { class: "kt-menu-item kt-has-sub", tabindex: 0 },
          h("span", {}, item.label), h("span", { class: "kt-menu-key" }, "›"),
          h("div", { class: "kt-menu kt-submenu" }, this.menuItems(item.children)))
      }
      return h("button", { class: "kt-menu-item", onclick: () => { this.closeMenu(); item.run() } },
        h("span", {}, item.label), item.key ? h("span", { class: "kt-menu-key" }, item.key) : null)
    })
  }

  openMenu(event, items) {
    event.stopPropagation()
    this.ui.menu = { x: event.clientX, y: event.clientY, items }
    this.render()
  }

  closeMenu() {
    if (!this.ui.menu) return
    this.ui.menu = null
    this.render()
  }

  // Right-click on empty battlefield: table actions (the goldfish "playtester" menu).
  openFieldMenu(event, at) {
    this.openMenu(event, [
      { label: "Virar tudo", run: () => this.perform("tap_all", { tapped: true }) },
      { label: "Desvirar tudo", key: "U", run: () => this.perform("tap_all", { tapped: false }) },
      "-",
      { label: "Desvirar e comprar (manual)", run: () => this.perform("new_turn") },
      { label: "Proliferar todos os contadores", run: () => this.perform("proliferate") },
      "-",
      { label: "Adicionar token", children: [
        ...(this.deckTokens?.length
          ? [{ heading: "Do seu deck" }, ...this.deckTokens.map((t) => ({
              label: `${t.name}${t.power ? ` ${t.power}/${t.toughness}` : ""}`,
              run: () => this.perform("create_card", { card_id: t.id, token: true, ...at })
            }))]
          : [{ heading: "Seu deck não cria tokens" }]),
        "-",
        { label: "Buscar token…", run: () => this.openSearch({ token: true, ...at }) }
      ] },
      { label: "Adicionar carta da busca…", run: () => this.openSearch({ token: false, ...at }) },
      { label: "Criar carta personalizada…", run: () => this.openCustomCard(at) },
      "-",
      { label: "Grimório", children: this.libraryItems(this.me) },
      this.myTurn && this.view.turn_started ? { label: "Passar o turno", run: () => this.perform("pass_turn") } : { label: "Iniciar turno", key: "N", run: () => this.startTurn() }
    ])
  }

  libraryItems(seat) {
    return [
      { label: "Buscar no grimório…", run: () => { this.ui.searchFilter = ""; this.perform("peek", { search: true }) } },
      "-",
      { label: "Comprar 1", key: "D", run: () => this.perform("draw") },
      { label: "Comprar N…", run: () => { const n = askCount("Comprar quantas?", 7); if (n) this.perform("draw", { count: n }) } },
      { label: "Olhar o topo…", run: () => this.promptPeek(seat) },
      { label: "Moer N…", run: () => { const n = askCount("Moer quantas cartas?", 1); if (n) this.perform("mill", { count: n }) } },
      { label: "Embaralhar", key: "S", run: () => this.perform("shuffle") },
      "-",
      { label: `${seat.top_revealed ? "✓ " : ""}Jogar com o topo revelado`, run: () => this.perform("top_revealed", { revealed: !seat.top_revealed }) }
    ]
  }

  openCardMenu(event, instance, zone, seat) {
    const id = instance.id
    const card = this.card(instance)
    const face = this.face(instance)
    const own = seat.seat_id === this.seatIdValue
    const onField = zone === "battlefield"
    const counter = (key, delta) => this.perform("card_counter", { card_instance_id: id, key, delta })
    const pt = (power, toughness) => this.perform("modify_pt", { card_instance_id: id, power, toughness })
    const spot = () => (this.me.ready ? this.nextSpot(this.bandOf(instance)) : {})

    const moveTo = [
      !onField && { label: "Campo de batalha", run: () => this.move(id, "battlefield", spot()) },
      zone !== "hand" && { label: "Mão", run: () => this.move(id, "hand") },
      { label: "Topo do grimório", run: () => this.move(id, "library", { to_position: 0 }) },
      { label: "Fundo do grimório", run: () => this.move(id, "library", { to_position: -1 }) },
      zone !== "graveyard" && { label: "Cemitério", run: () => this.move(id, "graveyard") },
      zone !== "exile" && { label: "Exílio", run: () => this.move(id, "exile") },
      zone !== "command" && { label: "Zona de comando", run: () => this.move(id, "command") }
    ]
    if (onField) {
      const others = this.view.seats.filter((s) => s.ready && s.seat_id !== seat.seat_id)
      if (others.length) moveTo.push("-", { heading: "Dar o controle para" }, ...others.map((o) => ({ label: o.display_name, run: () => this.move(id, "battlefield", { to_seat_id: o.seat_id }) })))
    }

    const cardActions = [
      zone === "hand" && own && { label: "Jogar / conjurar", run: () => this.playFromHand(instance) },
      zone === "hand" && own && { label: "Revelar esta carta", run: () => this.revealIds([id]) },
      zone === "hand" && own && { label: "Revelar a mão", run: () => this.revealIds(this.me.zones.hand.map((c) => c.id)) },
      onField && instance.sick && { label: "Remover enjoo de invocação", run: () => this.perform("remove_sickness", { card_instance_id: id }) },
      onField && card?.double_faced && { label: "Transformar", run: () => this.perform("flip_card", { card_instance_id: id }) },
      onField && { label: instance.face_down ? "Virar para cima" : "Virar para baixo", run: () => this.perform("face_down", { card_instance_id: id, face_down: !instance.face_down }) }
    ].filter(Boolean)

    const counterKeys = [...new Set([...CARD_COUNTERS, ...Object.keys(instance.counters || {})])]
    const counters = counterKeys.flatMap((key) => [
      { label: `${key} +1`, run: () => counter(key, 1) },
      instance.counters?.[key] ? { label: `${key} −1`, run: () => counter(key, -1) } : null
    ]).concat("-", { label: "Outro contador…", run: () => { const key = window.prompt("Nome do contador (ex.: Imposto do comandante)"); if (key) counter(key, 1) } })

    const steps = [1, -1, 2, -2, 3, -3]
    const modified = instance.power_mod || instance.toughness_mod
    const copies = card && [1, 2, 3].map((n) => ({ label: `${n}×`, run: () => this.perform("create_card", { card_id: card.id, token: true, count: n, ...spot() }) }))
      .concat({ label: "N…", run: () => { const n = askCount("Quantas cópias?", 4); if (n) this.perform("create_card", { card_id: card.id, token: true, count: n }) } })

    this.openMenu(event, [
      onField && { label: instance.tapped ? "Desvirar" : "Virar (tap)", key: "T", run: () => this.perform("tap_card", { card_instance_id: id, tapped: !instance.tapped }) },
      { label: "Mover para", children: moveTo.filter(Boolean) },
      cardActions.length && { label: "Ações da carta", children: cardActions },
      (onField || zone === "command") && "-",
      (onField || zone === "command") && { label: "Adicionar contadores", children: counters },
      onField && { label: "Somar / subtrair poder", children: steps.map((n) => ({ label: signed(n), run: () => pt(n, 0) })) },
      onField && { label: "Somar / subtrair resistência", children: steps.map((n) => ({ label: signed(n), run: () => pt(0, n) })) },
      onField && { label: "Somar / subtrair +X/+X", children: [
        ...steps.map((n) => ({ label: `${signed(n)}/${signed(n)}`, run: () => pt(n, n) })),
        modified && "-",
        modified && { label: "Zerar modificadores", run: () => pt(-instance.power_mod, -instance.toughness_mod) }
      ] },
      "-",
      face && { label: "Ver detalhes da carta", run: () => this.openDetails(instance) },
      copies && { label: "Criar cópia como token", children: copies },
      { label: "Remover do jogo", run: () => { if (window.confirm(`Remover ${face?.name || "esta carta"} do jogo?`)) this.perform("remove_card", { card_instance_id: id }) } }
    ])
  }

  // Right-click on a card that's part of a multi-card selection.
  openSelectionMenu(event) {
    const ids = [...this.selection]
    const located = ids.map((id) => ({ id, ...this.locate(id) })).filter((l) => l.instance)
    const onField = located.filter((l) => l.zone === "battlefield")
    const myHand = located.filter((l) => l.zone === "hand" && l.seat.seat_id === this.seatIdValue)
    const done = (fn) => () => { fn(); this.clearSelection() }
    const each = (list, action, data) => list.forEach((l) => this.perform(action, { card_instance_id: l.id, ...data(l) }))

    this.openMenu(event, [
      { heading: `${ids.length} cartas selecionadas` },
      onField.length && { label: "Virar todas", run: done(() => each(onField, "tap_card", () => ({ tapped: true }))) },
      onField.length && { label: "Desvirar todas", run: done(() => each(onField, "tap_card", () => ({ tapped: false }))) },
      { label: "Mover todas para", children: [
        { label: "Campo de batalha", run: () => this.moveMany(ids, "battlefield") },
        { label: "Mão", run: () => this.moveMany(ids, "hand") },
        { label: "Topo do grimório", run: () => this.moveMany(ids, "library", { to_position: 0 }) },
        { label: "Fundo do grimório", run: () => this.moveMany(ids, "library", { to_position: -1 }) },
        { label: "Cemitério", run: () => this.moveMany(ids, "graveyard") },
        { label: "Exílio", run: () => this.moveMany(ids, "exile") },
        { label: "Zona de comando", run: () => this.moveMany(ids, "command") }
      ] },
      onField.length && { label: "Adicionar contadores em todas", children: CARD_COUNTERS.map((key) => ({
        label: `${key} +1`, run: done(() => each(onField, "card_counter", () => ({ key, delta: 1 })))
      })) },
      onField.length && { label: "Somar / subtrair +X/+X em todas", children: [1, -1, 2, -2].map((n) => ({
        label: `${signed(n)}/${signed(n)}`, run: done(() => each(onField, "modify_pt", () => ({ power: n, toughness: n })))
      })) },
      myHand.length && { label: "Revelar as da mão", run: done(() => this.revealIds(myHand.map((l) => l.id))) },
      "-",
      { label: "Remover todas do jogo", run: () => {
        if (window.confirm(`Remover ${ids.length} cartas do jogo?`)) done(() => each(located, "remove_card", () => ({})))()
      } },
      { label: "Limpar seleção", key: "Esc", run: () => this.clearSelection() }
    ])
  }

  // Adds a counter to the player's bar (it then has its own − [total] + controls), or
  // removes one from it.
  openPlayerCounterMenu(event, seat) {
    const target = { target_seat_id: seat.seat_id }
    const present = Object.keys(seat.counters || {})
    const add = (key) => this.perform("player_counter", { key, delta: 1, ...target })
    this.openMenu(event, [
      { heading: `Contadores de ${seat.display_name}` },
      ...PLAYER_COUNTERS.filter((key) => !present.includes(key)).map((key) => ({ label: `Adicionar ${key}`, run: () => add(key) })),
      { label: "Adicionar outro…", run: () => { const key = window.prompt("Nome do contador"); if (key) add(key) } },
      present.length && "-",
      ...present.map((key) => ({ label: `Remover ${key}`, run: () => this.perform("player_counter", { key, remove: true, ...target }) }))
    ])
  }

  openDiceMenu(event) {
    this.openMenu(event, [
      { label: "Moeda", run: () => this.perform("roll_dice", { sides: 2 }) },
      { label: "d6", run: () => this.perform("roll_dice", { sides: 6 }) },
      { label: "d20", run: () => this.perform("roll_dice", { sides: 20 }) },
      { label: "Outro dado…", run: () => { const n = askCount("Quantos lados?", 12); if (n) this.perform("roll_dice", { sides: n }) } }
    ])
  }

  openViewer(viewer) {
    this.ui.viewer = viewer
    this.render()
  }

  // --- modals with inputs (built once, never redrawn) -----------------------------

  openModal(title, body) {
    const close = () => this.el.modals.replaceChildren()
    this.el.modals.replaceChildren(h("div", { class: "kt-overlay kt-modal-overlay", onclick: (e) => { if (e.target === e.currentTarget) close() } },
      h("div", { class: "kt-viewer kt-modal" },
        h("header", { class: "kt-dialog-header" }, h("h2", {}, title), h("button", { class: "kt-icon-btn", onclick: close }, "✕")),
        body)))
    this.el.modals.querySelector("input")?.focus()
    return close
  }

  openSearch({ token, x, y }) {
    const input = h("input", { type: "search", class: "kt-input", placeholder: token ? "Treasure, Soldier, Clue…" : "Nome da carta…" })
    const results = h("ul", { class: "kt-search-results" })
    let timer = null
    let close = null
    input.addEventListener("input", () => {
      clearTimeout(timer)
      timer = setTimeout(async () => {
        const response = await fetch(`/cards/search?q=${encodeURIComponent(input.value)}`, { headers: { Accept: "application/json" } })
        const cards = response.ok ? await response.json() : []
        fill(results, cards.map((card) => h("li", {},
          h("button", { class: "kt-menu-item", onclick: () => { close(); this.perform("create_card", { card_id: card.id, token, x, y }) } },
            h("span", {}, card.name), h("span", { class: "kt-menu-key" }, card.type_line || "")))))
      }, 200)
    })
    close = this.openModal(token ? "Adicionar token" : "Adicionar carta", h("div", {}, input, results))
  }

  openCustomCard({ x, y }) {
    const field = (name, label, attrs = {}) => h("label", { class: "kt-field" }, label, h("input", { name, class: "kt-input", ...attrs }))
    let close = null
    const form = h("form", { class: "kt-form", onsubmit: (e) => {
      e.preventDefault()
      const data = Object.fromEntries(new FormData(form))
      close()
      this.perform("create_card", { custom: data, token: false, x, y })
    } },
      field("name", "Nome", { required: true, maxlength: 60 }),
      field("type_line", "Tipo", { placeholder: "Creature — Elemental", maxlength: 60 }),
      h("div", { class: "kt-row" }, field("power", "Poder", { maxlength: 4 }), field("toughness", "Resistência", { maxlength: 4 })),
      h("button", { type: "submit", class: "kt-btn kt-btn-primary" }, "Criar"))
    close = this.openModal("Criar carta personalizada", form)
  }

  openDetails(instance) {
    const card = this.card(instance)
    const faces = card ? card.faces : [this.face(instance)]
    this.openModal(card?.name || faces[0].name, h("div", { class: "kt-details" },
      faces.map((face) => h("div", { class: "kt-details-face" },
        face.image ? h("img", { src: face.image, alt: face.name }) : null,
        h("div", {},
          h("h3", {}, face.name, face.mana_cost ? h("span", { class: "kt-muted" }, ` ${face.mana_cost}`) : null),
          h("p", { class: "kt-muted" }, face.type_line || ""),
          face.oracle_text ? h("p", { class: "kt-oracle" }, face.oracle_text) : null,
          face.power ? h("p", {}, `${face.power}/${face.toughness}`) : null,
          face.loyalty ? h("p", {}, `Lealdade ${face.loyalty}`) : null))),
      card ? h("a", { href: `https://scryfall.com/search?q=${encodeURIComponent(`!"${card.name}"`)}`, target: "_blank", rel: "noopener", class: "kt-link" }, "Abrir no Scryfall ↗") : null))
  }

  // --- prompts & small actions ----------------------------------------------------

  promptPeek(seat) {
    const own = seat.seat_id === this.seatIdValue
    const n = askCount(own ? "Olhar quantas cartas do topo do seu grimório?" : `Olhar quantas cartas do topo do grimório de ${seat.display_name}?`, own ? 3 : 1)
    if (n) this.perform("peek", { count: n, target_seat_id: seat.seat_id })
  }

  revealIds(ids) {
    if (ids.length) this.perform("reveal", { card_instance_ids: ids })
  }

  toggleLog() {
    this.ui.logOpen = !this.ui.logOpen
    this.render()
  }

  openDecklist() {
    if (!this.decklistDialogTarget.open) this.decklistDialogTarget.showModal()
  }

  closeDecklist() {
    this.decklistErrorValue = false
    this.decklistDialogTarget.close()
  }

  handleKey(event) {
    if (!this.view?.seats || !this.me?.ready) return
    if (event.key === "Control") {
      // `hovered` can be stale when a redraw removed the card under the pointer
      // without a mouseleave; only select what is really under it now.
      const id = this.hovered?.instance.id
      if (id && this.rootTarget.querySelector(`[data-id="${CSS.escape(id)}"]:hover`)) this.select(id)
      return
    }
    if (event.target.closest("input, textarea, select, dialog") || event.metaKey || event.ctrlKey || event.altKey) return
    if (event.key === "Escape") {
      if (this.me.peek && !this.ui.menu && !this.el.modals.childElementCount) {
        this.ui.searchFilter = ""
        this.perform("stop_peek")
      }
      this.clearSelection()
      this.ui.viewer = null
      this.ui.menu = null
      this.el.modals.replaceChildren()
      return this.render()
    }
    const hovered = this.hovered
    const actions = {
      d: () => this.perform("draw"),
      u: () => this.perform("tap_all", { tapped: false }),
      s: () => this.perform("shuffle"),
      n: () => this.startTurn(),
      t: () => hovered?.zone === "battlefield" && this.perform("tap_card", { card_instance_id: hovered.instance.id, tapped: !hovered.instance.tapped })
    }
    const action = actions[event.key.toLowerCase()]
    if (!action) return
    event.preventDefault()
    action()
  }

  // --- zoom & toasts --------------------------------------------------------------

  showZoom(instance) {
    if (this.dragging || instance.face_down) return
    const card = this.card(instance)
    if (!card) return
    const faces = card.double_faced ? card.faces : card.faces.slice(0, 1)
    const current = Math.min(instance.face_index || 0, faces.length - 1)
    fill(this.el.zoom, faces.filter((f) => f.image).map((face, i) =>
      h("img", { src: face.image, alt: face.name, class: i === current ? "" : "kt-zoom-other" })))
    this.el.zoom.classList.add("kt-zoom-visible")
  }

  hideZoom() {
    this.el?.zoom.classList.remove("kt-zoom-visible")
  }

  toast(message, kind = "error") {
    const el = h("div", { class: `kt-toast kt-toast-${kind}` }, message)
    document.body.append(el)
    setTimeout(() => el.remove(), 4000)
  }
}

// "3/3", adjusted by +1/+1 and -1/-1 counters and manual modifiers; non-numeric
// printed values ("*") are shown as printed.
function powerToughness(instance, face) {
  if (face.power == null && face.toughness == null) return null
  const counters = instance.counters || {}
  const boost = (counters["+1/+1"] || 0) - (counters["-1/-1"] || 0)
  const dp = boost + (instance.power_mod || 0)
  const dt = boost + (instance.toughness_mod || 0)
  const value = (printed, delta) => (/^-?\d+$/.test(printed ?? "") ? String(parseInt(printed, 10) + delta) : (printed ?? "?"))
  return { text: `${value(face.power, dp)}/${value(face.toughness, dt)}`, modified: dp !== 0 || dt !== 0 }
}

function clamp(value, min, max) { return Math.min(max, Math.max(min, value)) }
function round(value) { return Math.round(value * 10) / 10 }
function signed(n) { return n > 0 ? `+${n}` : `${n}` }
// "Talrand, Sky Summoner" -> "Talrand"; "Elesh Norn // The Argent Etchings" -> "Elesh Norn"
function shortName(name) { return name.split(" // ")[0].split(",")[0] }
function shortCounter(key) { return key.length > 7 ? key.slice(0, 7) : key }

function askCount(question, fallback) {
  const answer = window.prompt(question, String(fallback))
  if (answer === null) return null
  const n = parseInt(answer, 10)
  return Number.isFinite(n) && n > 0 ? n : null
}
