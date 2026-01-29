import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (typeof TomSelect === "undefined") return

    this.select = new TomSelect(this.element, {
      create: false,
      allowEmptyOption: true,
      onChange: () => {
        this.element.closest("form")?.requestSubmit()
      }
    })
  }

  disconnect() {
    this.select?.destroy()
  }
}
