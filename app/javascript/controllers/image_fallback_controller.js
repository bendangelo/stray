import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "primary", "fallback" ]
  static values = { fallbackSrc: String }

  connect() {
    this.fallbackApplied = false
  }

  onError() {
    if (this.fallbackApplied) return
    this.fallbackApplied = true

    if (this.hasFallbackTarget) {
      this.primaryTarget.classList.add("hidden")
      this.fallbackTarget.classList.remove("hidden")
    } else if (this.fallbackSrcValue) {
      this.primaryTarget.src = this.fallbackSrcValue
    }
  }
}
