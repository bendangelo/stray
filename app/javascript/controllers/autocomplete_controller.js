import Autocomplete from "stimulus-autocomplete"

export default class extends Autocomplete {
  open() {
    super.open()
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    super.close()
    this.inputTarget.setAttribute("aria-expanded", "false")
  }

  commit(selected) {
    const href = selected.getAttribute("data-autocomplete-href")
    if (href) {
      this.hideAndRemoveOptions()
      Turbo.visit(href)
      return
    }
    super.commit(selected)
  }
}
