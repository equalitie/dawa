import { Controller } from "@hotwired/stimulus";
export default class extends Controller {
  static targets = ["growButton", "shrinkButton"];

  connect() {
    // does not work because iframes capture keyboard events.
    // this.element.addEventListener("keydown", (e) => {
    //   if (e.key === "Escape") {
    //     this.elementTarget.classList.remove("fill-viewport");
    //   }
    // });
  }
  expand() {
    this.element.classList.add("fill-viewport");
    this.growButtonTarget.classList.add("d-none");
    this.shrinkButtonTarget.classList.remove("d-none");
  }
  shrink() {
    this.element.classList.remove("fill-viewport");
    this.growButtonTarget.classList.remove("d-none");
    this.shrinkButtonTarget.classList.add("d-none");
  }
}
