import { Controller } from "@hotwired/stimulus"

// Suggests the pasted list's card names in the commander field, so picking the
// commander is a matter of choosing one of your own cards.
export default class extends Controller {
  static targets = ["list", "commanderOptions"]

  connect() {
    this.refreshCommanderOptions()
  }

  refreshCommanderOptions() {
    if (!this.hasCommanderOptionsTarget) return

    const names = this.listTarget.value
      .split("\n")
      .map((line) => line.trim().match(/^\d+\s+(.+?)(?:\s+\([A-Za-z0-9]{2,5}\)\s*[A-Za-z0-9-]*)?$/))
      .filter(Boolean)
      .map((match) => match[1])

    this.commanderOptionsTarget.replaceChildren(
      ...[...new Set(names)].map((name) => Object.assign(document.createElement("option"), { value: name }))
    )
  }
}
