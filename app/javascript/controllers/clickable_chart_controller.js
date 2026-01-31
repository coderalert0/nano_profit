import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { urls: Object }

  connect() {
    this.clickHandler = this.handleClick.bind(this)
    this.element.addEventListener("click", this.clickHandler)
    this.element.style.cursor = "pointer"
  }

  disconnect() {
    this.element.removeEventListener("click", this.clickHandler)
  }

  handleClick(event) {
    const chartkickChart = Object.values(Chartkick.charts).find(c =>
      this.element.contains(c.element)
    )
    if (!chartkickChart) return

    const chart = chartkickChart.chart || chartkickChart.getChartObject()
    if (!chart) return

    const elements = chart.getElementsAtEventForMode(event, "nearest", { intersect: true }, false)
    if (elements.length === 0) return

    const label = chart.data.labels[elements[0].index]
    const url = this.urlsValue[label]
    if (url) window.location.href = url
  }
}
