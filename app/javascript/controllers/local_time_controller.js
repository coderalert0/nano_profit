import { Controller } from "@hotwired/stimulus"

const FORMAT_OPTIONS = {
  month: "short",
  day: "numeric",
  year: "numeric",
  hour: "numeric",
  minute: "2-digit",
  second: "2-digit"
}

export default class extends Controller {
  connect() {
    const date = new Date(this.element.dateTime)
    if (!isNaN(date)) {
      this.element.textContent = new Intl.DateTimeFormat(undefined, FORMAT_OPTIONS).format(date)
    }
  }
}
