// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";

import "@popperjs/core"; // must come before bootstrap
import "bootstrap"; // see https://github.com/twbs/bootstrap/tree/main/js/src

// vega charts
import "vega";
import "vega-lite";
import "vega-embed";

// Non-blocking: let the UMD globals (window.vega, window.vegaLite,
// window.vegaEmbed) be assigned after the importmap modules execute, then
// notify the vega.rb inline embed scripts (which register a listener for
// this event as a fallback when window.vegaEmbed isn't ready yet).
window.dispatchEvent(new Event("vega:load"));

//
// DOM initializations
//
function domLoaded(event) {
  // Activate all bootstrap tooltips
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
    bootstrap.Tooltip.getOrCreateInstance(el);
  });

  // select text with custom data-select-text attribute
  document.querySelectorAll('[data-select-text="true"]').forEach((el) => {
    el.setSelectionRange(0, el.value.length);
  });

  // this prevents the hidden close button from still having focus.
  document.querySelectorAll(".modal").forEach((modal) => {
    modal.addEventListener("hide.bs.modal", () => {
      document.activeElement.blur();
    });
  });
}

document.addEventListener("turbo:load", domLoaded);
document.addEventListener("turbo:frame-load", domLoaded);
