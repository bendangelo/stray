import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "sidebar", "backdrop" ]
  static values = { open: Boolean }

  toggle() {
    this.openValue = !this.openValue
  }

  close() {
    this.openValue = false
  }

  openValueChanged() {
    if (this.openValue) {
      this.sidebarTarget.classList.remove("-translate-x-full")
      this.backdropTarget.classList.remove("hidden")
    } else {
      this.sidebarTarget.classList.add("-translate-x-full")
      this.backdropTarget.classList.add("hidden")
    }
  }
}
