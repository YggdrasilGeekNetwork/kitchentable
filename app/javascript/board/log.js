// Turns table log events into readable Portuguese lines.
// Portuguese contracts "de"/"para" with the article ("da mão", "do cemitério").
const FROM_ZONE = {
  library: "do grimório", hand: "da mão", battlefield: "do campo de batalha", stack: "da pilha",
  graveyard: "do cemitério", exile: "do exílio", command: "da zona de comando", revealed: "das reveladas"
}
const TO_ZONE = {
  library: "o grimório", hand: "a mão", battlefield: "o campo de batalha", stack: "a pilha",
  graveyard: "o cemitério", exile: "o exílio", command: "a zona de comando"
}

export function describeEvent(event, view) {
  const who = seatName(view, event.seat_id)
  const p = event.payload || {}
  const card = cardName(view, p.card_id)

  switch (event.event_type) {
    case "start_game": return `${who} embaralhou o deck e comprou 7 (${p.library_size} no grimório)`
    case "keep_hand": return `${who} manteve a mão com ${p.hand_size} cartas${p.mulligan_count ? ` após ${p.mulligan_count} mulligan(s) — deve colocar ${p.mulligan_count} no fundo` : ""}`
    case "mulligan": return `${who} fez mulligan (${p.mulligan_count})`
    case "draw": return `${who} comprou ${plural(p.count, "carta", "cartas")}`
    case "mill": return `${who} moeu ${plural(p.count, "carta", "cartas")}`
    case "shuffle": return `${who} embaralhou o grimório`
    case "untap_all": return `${who} desvirou suas permanentes`
    case "tap_all": return `${who} virou todas as suas permanentes`
    case "new_turn": return `${who} começou o turno (desvirou e comprou ${p.drew ? "1 carta" : "nada — grimório vazio"})`
    case "proliferate": return `${who} proliferou (${plural(p.permanents, "permanente", "permanentes")})`
    case "pt_modifier": return `${who}: ${card || "uma carta"} ${signed(p.power)}/${signed(p.toughness)}`
    case "remove_card": return `${who} removeu ${card || "uma carta"} do jogo`
    case "tap_card": return `${who} ${p.tapped ? "virou" : "desvirou"} ${card || "uma carta"}`
    case "move_card": return describeMove(view, who, card, p)
    case "life_change": return `${who} ${p.delta >= 0 ? "+" : ""}${p.delta} de vida${p.target_seat_id !== event.seat_id ? ` em ${seatName(view, p.target_seat_id)}` : ""} (→ ${p.life_total})`
    case "player_counter": if (p.removed) return `${who} removeu o contador ${p.key} de ${seatName(view, p.target_seat_id)}`
      return `${who}: ${p.key} ${p.delta >= 0 ? "+" : ""}${p.delta} em ${seatName(view, p.target_seat_id)} (→ ${p.value})`
    case "commander_damage": return `${seatName(view, p.target_seat_id)} ${p.delta > 0 ? "recebeu" : "teve corrigido"} ${Math.abs(p.delta)} de dano de comandante de ${card || "um comandante"} (total ${p.total}, vida ${p.life_total})${p.lethal ? " — LETAL" : ""}`
    case "card_counter": return `${who}: ${p.key} ${p.delta >= 0 ? "+" : ""}${p.delta} em ${card || "uma carta"} (→ ${p.value})`
    case "flip_card": return `${who} transformou ${card || "uma carta"}`
    case "face_down": return p.face_down ? `${who} virou uma carta para baixo` : `${who} desvirou para cima ${card || "uma carta"}`
    case "reveal": return `${who} revelou ${plural(p.count, "carta", "cartas")}${p.owner_seat_id !== event.seat_id ? ` de ${seatName(view, p.owner_seat_id)}` : ""}`
    case "peek": {
      const top = p.count === 1 ? "a carta do topo" : `as ${p.count} cartas do topo`
      return p.target_seat_id === event.seat_id
        ? `${who} está olhando ${top} do próprio grimório`
        : `${who} está olhando ${top} do grimório de ${seatName(view, p.target_seat_id)}`
    }
    case "create_card": return `${who} criou ${p.count}× ${card || p.custom_name || "carta"}${p.token ? " (token)" : ""}`
    case "dice_roll": return p.sides === 2
      ? `${who} jogou uma moeda: ${p.result === 1 ? "cara" : "coroa"}`
      : `${who} rolou um d${p.sides}: ${p.result}`
    case "restart_requested": return `${who} pediu para reiniciar o jogo`
    case "restart_declined": return `${who} recusou reiniciar o jogo`
    case "restart": return `Jogo reiniciado — ${seatName(view, p.first_seat_id)} foi sorteado para começar`
    case "peek_remaining": return `${who} colocou ${plural(p.count, "carta", "cartas")} no ${p.placement === "top" ? "topo" : "fundo"} do grimório${p.target_seat_id !== event.seat_id ? ` de ${seatName(view, p.target_seat_id)}` : ""}, em ordem aleatória`
    case "top_revealed": return p.revealed ? `${who} passou a jogar com o topo do grimório revelado` : `${who} parou de revelar o topo do grimório`
    case "library_search": return `${who} está buscando no próprio grimório`
    case "start_turn": return p.out_of_turn
      ? `${who} jogou um turno fora da sua vez (seu turno ${p.seat_turn}) — desvirou e comprou`
      : `${who} iniciou o seu turno ${p.seat_turn} — desvirou e comprou`
    case "pass_turn": return p.new_round
      ? `Rodada ${p.round} começou — vez de ${seatName(view, p.active_seat_id)}`
      : `Vez de ${seatName(view, p.active_seat_id)}`
    case "chat": return `${who}: ${p.message}`
    default: return `${who}: ${event.event_type}`
  }
}

function describeMove(view, who, card, p) {
  const what = card || "uma carta"
  const owner = p.to_seat_id !== p.from_seat_id ? ` de ${seatName(view, p.to_seat_id)}` : ""
  if (p.to_zone === "battlefield" && p.from_zone === "battlefield") return `${who} passou ${what} para o campo${owner}`
  if (p.to_zone === "stack") return `${who} conjurou ${what}`
  if (p.from_zone === "stack" && p.to_zone === "hand") return `${who} devolveu ${what} da pilha para a mão`
  if (p.from_zone === "stack") return `${what} resolveu e foi para ${TO_ZONE[p.to_zone]}`
  if (p.to_zone === "library") return `${who} colocou ${what} no ${p.to_bottom ? "fundo" : "topo"} do grimório${owner}`
  return `${who} moveu ${what} ${FROM_ZONE[p.from_zone]} para ${TO_ZONE[p.to_zone]}${owner}`
}

export function seatName(view, seatId) {
  return view.seats.find((s) => s.seat_id === String(seatId))?.display_name || "?"
}

function cardName(view, cardId) {
  return cardId ? view.cards[String(cardId)]?.name : null
}

function signed(n) {
  return n >= 0 ? `+${n}` : `${n}`
}

function plural(n, one, many) {
  return `${n} ${n === 1 ? one : many}`
}
