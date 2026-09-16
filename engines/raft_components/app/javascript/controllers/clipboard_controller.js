// https://www.stimulus-components.com/docs/stimulus-clipboard

import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button", "source"];
  static values = {
    successContent: String,
    successDuration: {
      type: Number,
      default: 2000,
    },
    mode: {
      type: String,
      default: "text",
    },
  };

  connect() {
    if (!this.hasButtonTarget) return;
    this.originalContent = this.buttonTarget.innerHTML;
  }

  copy(event) {
    event.preventDefault();
    navigator.clipboard.writeText(this.getText()).then(() => this.copied());
  }

  getText() {
    return (
      (this.modeValue == "text"
        ? this.sourceTarget.innerText
        : this.sourceTarget.innerHTML) || this.sourceTarget.value
    );
  }

  copied() {
    if (!this.hasButtonTarget) return;

    if (this.timeout) {
      clearTimeout(this.timeout);
    }

    this.buttonTarget.innerHTML = this.successContentValue;

    this.timeout = setTimeout(() => {
      this.buttonTarget.innerHTML = this.originalContent;
    }, this.successDurationValue);
  }
}
