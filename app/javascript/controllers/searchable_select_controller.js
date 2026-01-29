import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (typeof TomSelect === "undefined") return

    const isMultiple = this.element.hasAttribute("multiple")

    this.select = new TomSelect(this.element, {
      create: false,
      allowEmptyOption: !isMultiple,
      plugins: isMultiple ? [ "remove_button" ] : [],
      placeholder: this.element.dataset.placeholder || "Search...",
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
