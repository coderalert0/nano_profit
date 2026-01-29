import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]

  open() {
    this.modalTarget.showModal()
  }

  close() {
    this.modalTarget.close()
  }

  clickOutside(event) {
    if (event.target === this.modalTarget) {
      this.modalTarget.close()
    }
  }
}
