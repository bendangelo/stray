import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    text: String,
    copiedDuration: { type: Number, default: 1500 }
  }

  copy() {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(this.textValue)
        .then(() => this.showCopied())
        .catch(() => this.fallbackCopy())
    } else {
      this.fallbackCopy()
    }
  }

  showCopied() {
    const btn = this.element.querySelector("button")
    if (!btn) return
    const original = btn.innerHTML
    btn.innerHTML = "Copied!"
    setTimeout(() => { btn.innerHTML = original }, this.copiedDurationValue)
  }

  fallbackCopy() {
    const ta = document.createElement("textarea")
    ta.value = this.textValue
    ta.style.position = "fixed"
    ta.style.opacity = "0"
    document.body.appendChild(ta)
    ta.select()
    try { document.execCommand("copy") } catch (e) { /* noop */ }
    document.body.removeChild(ta)
    this.showCopied()
  }
}
