import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { itemId: Number }
  static targets = ["input", "results"]

  connect() {
    this.highlightIndex = -1
    this.debounceTimer = null
  }

  toggle(event) {
    event.preventDefault()
    if (this.hasInputTarget) {
      this.inputTarget.focus()
      return
    }

    const form = document.createElement("div")
    form.className = "flex flex-col gap-1 mt-1"
    form.innerHTML = `
      <div class="flex gap-1">
        <input type="text" placeholder="tag name"
          data-${this.identifier}-target="input"
          data-action="keydown.esc->${this.identifier}#close keydown.enter->${this.identifier}#submit keydown ArrowDown->${this.identifier}#moveHighlight:prevent keydown ArrowUp->${this.identifier}#moveHighlight:prevent input->${this.identifier}#search"
          class="flex-1 h-8 px-2 text-xs border-3 border-charcoal rounded-md bg-athens-400 text-charcoal focus:outline-none" autocomplete="off">
        <button data-action="${this.identifier}#submit"
          class="h-8 px-3 bg-carrot-500 text-white text-xs rounded-md border-3 border-charcoal">Add</button>
      </div>
      <ul data-${this.identifier}-target="results"
        class="hidden border-3 border-charcoal rounded-md bg-athens-400 text-xs max-h-32 overflow-y-auto"></ul>
    `
    this.element.appendChild(form)
    this.inputTarget.focus()
  }

  search() {
    const query = this.inputTarget.value.trim()
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.fetchResults(query), 150)
  }

  fetchResults(query) {
    if (query.length < 1) {
      this.hideResults()
      return
    }

    fetch(`/tags/search?q=${encodeURIComponent(query)}`)
      .then(response => response.json())
      .then(tags => this.renderResults(tags, query))
  }

  renderResults(tags, query) {
    this.highlightIndex = -1
    this.resultsTarget.innerHTML = ""
    let hasExact = false

    tags.slice(0, 5).forEach((tag, i) => {
      if (tag.name.toLowerCase() === query.toLowerCase()) hasExact = true
      const li = document.createElement("li")
      li.className = "px-2 py-1 cursor-pointer hover:bg-athens-300 hover:text-carrot-600"
      li.dataset.action = "click->" + this.identifier + "#select"
      li.dataset.index = i
      li.textContent = tag.name
      this.resultsTarget.appendChild(li)
    })

    if (!hasExact && query.length > 0) {
      const li = document.createElement("li")
      li.className = "px-2 py-1 cursor-pointer hover:bg-athens-300 hover:text-carrot-600 border-t-3 border-charcoal"
      li.dataset.action = this.identifier + "#submit"
      li.dataset.index = tags.length
      li.textContent = `Create "${query}"`
      this.resultsTarget.appendChild(li)
    }

    if (this.resultsTarget.children.length > 0) {
      this.resultsTarget.classList.remove("hidden")
    } else {
      this.hideResults()
    }
  }

  moveHighlight(event) {
    const items = this.resultsTarget.children
    if (items.length === 0) return

    if (event.key === "ArrowDown") {
      this.highlightIndex = Math.min(this.highlightIndex + 1, items.length - 1)
    } else if (event.key === "ArrowUp") {
      this.highlightIndex = Math.max(this.highlightIndex - 1, -1)
    }

    Array.from(items).forEach((li, i) => {
      li.classList.toggle("bg-mint", i === this.highlightIndex)
    })

    if (this.highlightIndex >= 0) {
      items[this.highlightIndex].scrollIntoView({ block: "nearest" })
    }
  }

  select(event) {
    event.preventDefault()
    const li = event.target.closest("li")
    if (!li) return
    this.inputTarget.value = li.textContent
    this.submit(event)
  }

  submit(event) {
    event.preventDefault()
    const items = this.resultsTarget.children
    const highlighted = this.highlightIndex >= 0 ? items[this.highlightIndex] : null
    const name = (highlighted?.dataset.action?.includes("#select") ? highlighted.textContent : this.inputTarget.value).trim().toLowerCase()
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

  hideResults() {
    if (this.hasResultsTarget) {
      this.resultsTarget.classList.add("hidden")
      this.resultsTarget.innerHTML = ""
    }
  }

  close(event) {
    event?.preventDefault()
    if (this.hasInputTarget) {
      this.inputTarget.closest("div").parentElement.remove()
    }
  }

  disconnect() {
    clearTimeout(this.debounceTimer)
  }
}
