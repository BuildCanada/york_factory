import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }
  static targets = ["status"]

  async trigger() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    this.statusTarget.textContent = "Translating..."

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": token,
          "Accept": "application/json"
        }
      })

      if (response.ok) {
        this.statusTarget.textContent = "Translation queued"
      } else {
        this.statusTarget.textContent = "Failed to queue translation"
      }
    } catch {
      this.statusTarget.textContent = "Error"
    }
  }
}
