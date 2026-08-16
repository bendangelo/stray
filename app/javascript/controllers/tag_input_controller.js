import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { itemId: Number }
  static targets = ["input", "results"]

  toggle(event) {
    event.preventDefault()
    if (this.hasInputTarget) {
      this.inputTarget.focus()
      return
    }

    const form = document.createElement("div")
    form.className = "flex gap-1 mt-1"
    form.innerHTML = `
      <input type="text" placeholder="tag name"
        data-${this.identifier}-target="input"
        data-action="keydown.esc->${this.identifier}#close keydown.enter->${this.identifier}#submit input->${this.identifier}#search"
        class="flex-1 h-8 px-2 text-xs border-3 border-charcoal rounded-md bg-athens-400 text-charcoal focus:outline-none">
      <button data-action="${this.identifier}#submit"
        class="h-8 px-3 bg-carrot-500 text-white text-xs rounded-md border-3 border-charcoal">Add</button>
    `
    this.element.appendChild(form)
    this.inputTarget.focus()
  }

  search() {
    const query = this.inputTarget.value
    if (query.length < 1) return

    fetch(`/tags/search?q=${encodeURIComponent(query)}`)
      .then(response => response.json())
      .then(tags => {
        // Simple: show first match as a datalist or just let user type freely
      })
  }

  submit(event) {
    event.preventDefault()
    const name = this.inputTarget.value.trim().toLowerCase()
    if (!name) return

    const formData = new FormData()
    formData.append("tagging[item_id]", this.itemIdValue)
    formData.append("tagging[tag_name]", name)

    fetch("/taggings", {
      method: "POST",
      headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
      body: formData
    }).then(() => this.close())
  }

  close(event) {
    event?.preventDefault()
    if (this.hasInputTarget) {
      this.inputTarget.closest("div").remove()
    }
  }
}
