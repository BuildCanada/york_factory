import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  connect() {
    this.timer = setInterval(() => {
      if (document.hidden || document.activeElement?.matches("input, select, textarea, button")) return
      Turbo.visit(window.location.href, { action: "replace" })
    }, 30000)
  }
  disconnect() { clearInterval(this.timer) }
}
