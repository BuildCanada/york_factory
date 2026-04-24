import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["items", "template"]

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML
    this.itemsTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    const item = event.currentTarget.closest("[data-list-item]")
    if (item) item.remove()
  }
}
