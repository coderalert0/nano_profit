import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (typeof TomSelect === "undefined") return

    this.select = new TomSelect(this.element, {
      create: false,
      allowEmptyOption: true,
      render: {
        no_results: () => '<div class="no-results">No results found</div>'
      },
      onChange: () => {
        this.element.closest("form")?.requestSubmit()
      }
    })
  }

  disconnect() {
    this.select?.destroy()
  }
}
