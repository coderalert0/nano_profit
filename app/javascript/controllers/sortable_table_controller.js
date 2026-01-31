import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.currentColumn = null
    this.ascending = true
  }

  sort(event) {
    const th = event.currentTarget
    const headers = Array.from(th.parentElement.children)
    const colIndex = headers.indexOf(th)
    const type = th.dataset.sortType || "text"

    if (this.currentColumn === colIndex) {
      this.ascending = !this.ascending
    } else {
      this.currentColumn = colIndex
      this.ascending = true
    }

    headers.forEach(h => {
      const ind = h.querySelector(".sort-indicator")
      if (ind) ind.textContent = ""
    })
    let indicator = th.querySelector(".sort-indicator")
    if (!indicator) {
      indicator = document.createElement("span")
      indicator.className = "sort-indicator ml-1 text-gray-400"
      th.appendChild(indicator)
    }
    indicator.textContent = this.ascending ? "▲" : "▼"

    const tbody = this.element.querySelector("tbody")
    if (!tbody) return
    const rows = Array.from(tbody.querySelectorAll("tr")).filter(
      row => !row.querySelector("td[colspan]")
    )

    rows.sort((a, b) => {
      const aCell = a.children[colIndex]
      const bCell = b.children[colIndex]
      let result

      if (type === "number") {
        result = this.parseNumber(aCell) - this.parseNumber(bCell)
      } else if (type === "date") {
        result = this.sortValue(aCell) - this.sortValue(bCell)
      } else {
        result = (aCell?.textContent || "").trim().localeCompare((bCell?.textContent || "").trim())
      }

      return this.ascending ? result : -result
    })

    rows.forEach(row => tbody.appendChild(row))
  }

  sortValue(cell) {
    return parseFloat(cell?.dataset.sortValue || "0") || 0
  }

  parseNumber(cell) {
    const cleaned = (cell?.textContent || "").trim().replace(/[$,%\s]/g, "")
    return parseFloat(cleaned) || 0
  }
}
