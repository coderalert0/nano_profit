import { Controller } from "@hotwired/stimulus"

const BASE_OPTIONS = {
  month: "short",
  day: "numeric",
  year: "numeric",
  hour: "numeric",
  minute: "2-digit",
  second: "2-digit"
}

export default class extends Controller {
  static values = { millis: { type: Boolean, default: true } }

  connect() {
    const date = new Date(this.element.dateTime)
    if (isNaN(date)) return

    const options = this.millisValue
      ? { ...BASE_OPTIONS, fractionalSecondDigits: 3 }
      : BASE_OPTIONS

    this.element.textContent = new Intl.DateTimeFormat(undefined, options).format(date)
  }
}
