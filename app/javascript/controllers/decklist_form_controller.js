import { Controller } from "@hotwired/stimulus"

// Mirrors CardCatalog::Interactions::ParseDecklistText, so the live count matches what
// the server will read: "4 Name", an optional "(SET) 123" suffix, section headers.
const LINE = /^(\d+)\s+(.+?)(?:\s+\([A-Za-z0-9]{2,5}\)\s*[A-Za-z0-9-]*)?$/
const SECTIONS = { deck: "main", mainboard: "main", commander: "main", sideboard: "side", companion: "side" }

// Suggests the pasted list's card names in the commander field, so picking the
// commander is a matter of choosing one of your own cards, and counts the list as
// it's typed (the server still does the real validation).
export default class extends Controller {
  static targets = ["list", "commanderOptions", "summary"]

  connect() {
    this.refresh()
  }

  refresh() {
    const { main, names, ignored } = parse(this.listTarget.value)

    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = main || ignored
        ? `${main} ${main === 1 ? "carta" : "cartas"} no deck${ignored ? ` · ${ignored} linha(s) não reconhecida(s) serão ignoradas` : ""}`
        : ""
    }

    if (!this.hasCommanderOptionsTarget) return
    this.commanderOptionsTarget.replaceChildren(
      ...[...new Set(names)].map((name) => Object.assign(document.createElement("option"), { value: name }))
    )
  }
}

function parse(text) {
  let section = "main"
  let main = 0
  let ignored = 0
  const names = []
  for (const raw of text.split("\n")) {
    const line = raw.trim()
    if (!line || line.startsWith("//") || line.startsWith("#")) continue
    const header = line.replace(/:$/, "").toLowerCase()
    if (header in SECTIONS) { section = SECTIONS[header]; continue }
    const match = line.match(LINE)
    if (!match) { ignored++; continue }
    names.push(match[2])
    if (section === "main") main += parseInt(match[1], 10)
  }
  return { main, names, ignored }
}
