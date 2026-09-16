//
// see contain_image_component.rb & _contain_image.scss
//
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["img", "pixel", "placeholder", "link"];
  static values = {
    src: String,
    href: String,
    text: String,
  };

  connect() {
    if (!this.srcValue) {
      this.showPlaceholder();
      return;
    }
    this.loadImage();
  }

  loadImage() {
    const img = this.imgTarget;
    img.src = this.srcValue;
    if (img.complete && img.naturalWidth > 0) {
      this.onLoaded();
      return;
    }
    img.addEventListener("load", () => this.onLoaded(), { once: true });
    img.addEventListener("error", () => this.onError(), { once: true });
  }

  onLoaded() {
    if (this.hasPixelTarget) {
      this.pixelTarget.classList.add("hidden");
    }
    this.imgTarget.classList.add("visible");
    if (this.hrefValue && this.hasLinkTarget) {
      this.linkTarget.style.display = "flex";
    }
  }

  onError() {
    this.showPlaceholder();
  }

  showPlaceholder() {
    if (this.hasPixelTarget) this.pixelTarget.style.display = "none";
    if (this.hasImgTarget) this.imgTarget.style.display = "none";
    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.style.display = "flex";
      this.placeholderTarget.textContent = this.textValue;
    }
  }
}
