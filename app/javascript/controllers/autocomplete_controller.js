import Autocomplete from "stimulus-autocomplete"

export default class extends Autocomplete {
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
