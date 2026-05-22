import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "row", "empty", "count"]

  connect() {
    this.apply()
  }

  apply() {
    const query = (this.hasInputTarget ? this.inputTarget.value : "").trim().toLowerCase()
    let visible = 0

    this.rowTargets.forEach((row) => {
      const haystack = (row.dataset.filterText || row.textContent || "").toLowerCase()
      const match = query === "" || haystack.includes(query)
      row.hidden = !match
      if (match) visible++
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visible !== 0
    }
    if (this.hasCountTarget) {
      this.countTarget.textContent = visible
    }
  }

  clear(event) {
    event.preventDefault()
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
      this.inputTarget.focus()
    }
    this.apply()
  }
}
