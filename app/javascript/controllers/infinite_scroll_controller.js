import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="infinite-scroll"
export default class extends Controller {
  static values = { url: String, page: { type: Number, default: 1 } }
  static targets = ["sentinel", "tbody"]

  connect() {
    this.loading = false
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) this.loadMore()
        })
      },
      { rootMargin: "200px" }
    )

    if (this.hasSentinelTarget) {
      this.observer.observe(this.sentinelTarget)
    }
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  sentinelTargetConnected(element) {
    this.observer?.observe(element)
  }

  sentinelTargetDisconnected(element) {
    this.observer?.unobserve(element)
  }

  async loadMore() {
    if (this.loading) return
    this.loading = true

    const nextPage = this.pageValue + 1
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("page", nextPage)

    try {
      const response = await fetch(url, {
        headers: {
          Accept: "text/html",
          "Turbo-Frame": "infinite-scroll-rows"
        }
      })

      if (!response.ok) return

      const html = await response.text()
      const template = document.createElement("template")
      template.innerHTML = html.trim()

      // Remove the current sentinel before appending new rows
      if (this.hasSentinelTarget) {
        this.sentinelTarget.remove()
      }

      // Extract rows from the response (inside turbo-frame if present)
      const frame = template.content.querySelector("turbo-frame")
      const source = frame || template.content
      const rows = source.querySelectorAll("tr")

      if (rows.length > 0) {
        rows.forEach((row) => this.tbodyTarget.appendChild(row))
        this.pageValue = nextPage
      }
    } finally {
      this.loading = false
    }
  }
}
