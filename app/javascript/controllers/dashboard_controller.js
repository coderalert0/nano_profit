import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static values = { organizationId: Number }

  connect() {
    this.channel = createConsumer().subscriptions.create(
      { channel: "OrganizationChannel" },
      {
        received: (data) => this.handleBroadcast(data)
      }
    )
  }

  disconnect() {
    if (this.channel) {
      this.channel.unsubscribe()
    }
  }

  handleBroadcast(data) {
    if (data.type === "event_processed") {
      this.refreshPage()
    }
  }

  refreshPage() {
    // Reload summary cards after a short delay to let the DB settle
    setTimeout(() => {
      fetch(window.location.href, { headers: { "Accept": "text/html" } })
        .then(response => response.text())
        .then(html => {
          const parser = new DOMParser()
          const doc = parser.parseFromString(html, "text/html")

          const ids = ["total-revenue", "total-cost", "total-margin", "margin-pct"]
          ids.forEach(id => {
            const newEl = doc.getElementById(id)
            const oldEl = document.getElementById(id)
            if (newEl && oldEl) {
              oldEl.textContent = newEl.textContent
              oldEl.className = newEl.className
            }
          })
        })
    }, 500)
  }
}
