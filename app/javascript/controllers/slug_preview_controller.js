import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { sourceId: String }

  connect() {
    this.source = document.getElementById(this.sourceIdValue)
    if (!this.source) return
    this.userEdited = this.inputTarget.value.trim().length > 0
    this.sourceHandler = () => this.syncFromSource()
    this.inputHandler = () => { this.userEdited = true }
    this.source.addEventListener("input", this.sourceHandler)
    this.inputTarget.addEventListener("input", this.inputHandler)
  }

  disconnect() {
    if (this.source && this.sourceHandler) {
      this.source.removeEventListener("input", this.sourceHandler)
    }
    if (this.inputTarget && this.inputHandler) {
      this.inputTarget.removeEventListener("input", this.inputHandler)
    }
  }

  syncFromSource() {
    if (this.userEdited) return
    this.inputTarget.value = parameterize(this.source.value || "")
  }
}

function parameterize(str) {
  return str
    .toString()
    .normalize("NFKD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
}
