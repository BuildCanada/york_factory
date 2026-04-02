import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["section"]

  toggle(event) {
    const key = event.currentTarget.dataset.sidebarKey
    const section = this.sectionTargets.find(
      (s) => s.dataset.sidebarKey === key
    )
    if (!section) return

    const isOpen = section.style.display !== "none"
    section.style.display = isOpen ? "none" : "block"

    try {
      const state = JSON.parse(localStorage.getItem("sidebar_state") || "{}")
      state[key] = !isOpen
      localStorage.setItem("sidebar_state", JSON.stringify(state))
    } catch (e) {
      // localStorage unavailable
    }

    event.currentTarget.querySelector(".chevron")?.classList.toggle("open", !isOpen)
  }

  connect() {
    try {
      const state = JSON.parse(localStorage.getItem("sidebar_state") || "{}")
      this.sectionTargets.forEach((section) => {
        const key = section.dataset.sidebarKey
        const isOpen = state[key] !== false
        section.style.display = isOpen ? "block" : "none"
        const toggle = this.element.querySelector(`[data-sidebar-key="${key}"][data-action]`)
        toggle?.querySelector(".chevron")?.classList.toggle("open", isOpen)
      })
    } catch (e) {
      // localStorage unavailable
    }
  }
}
