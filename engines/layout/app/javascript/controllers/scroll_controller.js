import { Controller } from "@hotwired/stimulus";

//
// as the user scrolls content, the --shrink-header-height value
// is set, which overrides the default --header-height.
//

export default class extends Controller {
  static targets = ["scroller"];

  initialize() {
    this.boundUpdate = this.throttle(this.update.bind(this));
    this.resizeObserver = new ResizeObserver(() => this.update());
  }

  scrollerTargetConnected(element) {
    this.scrollerTargets.forEach((el) => {
      el.addEventListener("scroll", this.boundUpdate, {
        passive: true,
      });
    });
    this.scrollerTargets.forEach((el) => {
      this.resizeObserver.observe(el);
    });
  }

  scrollerTargetDisconnected(element) {
    this.scrollerTargets.forEach((el) => {
      el.removeEventListener("scroll", this.boundUpdate);
    });
    this.scrollerTargets.forEach((el) => {
      this.resizeObserver.unobserve(el);
    });
  }

  disconnect() {
    this.resizeObserver?.disconnect();
  }

  getComputedProperty(property) {
    const computed = getComputedStyle(document.documentElement);
    const value = computed.getPropertyValue(property).trim();
    return parseFloat(value);
  }

  update() {
    const maxHeight = this.getComputedProperty("--header-height");
    const minHeight = this.getComputedProperty("--header-min-height");
    const scrollTop = Math.max(
      ...this.scrollerTargets.map((el) => el.scrollTop),
    );
    var newHeight = Math.max(minHeight, maxHeight - scrollTop / 16);
    newHeight = newHeight % 2 === 0 ? newHeight : newHeight + 1;
    document.documentElement.style.setProperty(
      "--shrink-header-height",
      `${newHeight}px`,
    );
  }

  //
  // limit callback() to get called at most once per animation frame.
  // otherwise, scroll event might trigger update() hundreds of times
  // per millisecond.
  //
  throttle(callback) {
    let ticking = false;
    return () => {
      if (!ticking) {
        window.requestAnimationFrame(() => {
          callback();
          ticking = false;
        });
        ticking = true;
      }
    };
  }
}
