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
      this.prependEvent(data)
      this.refreshPage()
    }
  }

  prependEvent(data) {
    const tbody = document.getElementById("events-table-body")
    if (!tbody) return

    const noEventsRow = document.getElementById("no-events-row")
    if (noEventsRow) noEventsRow.remove()

    const row = document.createElement("tr")
    row.className = "table-row bg-emerald-50"
    row.innerHTML = `
      <td class="py-2.5 pr-4 text-xs text-slate-500 whitespace-nowrap">${this.formatTime(data.occurred_at)}</td>
      <td class="py-2.5 pr-4 text-slate-700">${this.escapeHtml(data.customer_name)}</td>
      <td class="py-2.5 pr-4"><span class="badge badge-blue">${this.escapeHtml(data.event_type)}</span></td>
      <td class="py-2.5 pr-4 text-right">${this.formatCents(data.revenue_in_cents)}</td>
      <td class="py-2.5 pr-4 text-right">${this.formatCents(data.cost_in_cents)}</td>
      <td class="py-2.5 text-right font-medium ${data.margin_in_cents >= 0 ? 'text-green-600' : 'text-red-600'}">${this.formatCents(data.margin_in_cents)}</td>
    `
    tbody.prepend(row)

    setTimeout(() => { row.classList.remove("bg-emerald-50") }, 3000)
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

  formatCents(cents) {
    return "$" + (cents / 100).toFixed(2)
  }

  formatTime(isoString) {
    if (!isoString) return "-"
    const d = new Date(isoString)
    return new Intl.DateTimeFormat(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
      second: "2-digit"
    }).format(d)
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text || ""
    return div.innerHTML
  }
}
