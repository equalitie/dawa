import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button", "radio"];

  updateButtonText() {
    const checkedRadio = this.radioTargets.find((radio) => radio.checked);
    console.log("update", checkedRadio);
    if (checkedRadio) {
      const label =
        checkedRadio.dataset.label ||
        checkedRadio.nextElementSibling?.textContent ||
        checkedRadio.value;
      this.buttonTarget.textContent = label;
    }
  }
}
