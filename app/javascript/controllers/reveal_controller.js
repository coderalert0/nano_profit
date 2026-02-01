import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["masked", "content", "button"]

  toggle() {
    const isHidden = this.contentTarget.classList.contains("hidden")

    this.maskedTarget.classList.toggle("hidden", isHidden)
    this.contentTarget.classList.toggle("hidden", !isHidden)
    this.buttonTarget.textContent = isHidden ? "Hide" : "Show"
  }
}
