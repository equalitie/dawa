//
// This controller handles a lot of tasks for modal dialogs and
// offcanvas bootstrap elements.
//
// (1) show modal and offcanvas elements immediately when
//     loaded if they have the class .auto-open,
// (2) set value "true" to any input elements named "modal_context"
//     or add "modal_context=true" for "form" targets
// (3) initialize tooltips
// (4) properly sets autofocus
//
// Background: There is no way in bootstrap to show modal and offcanvas
// elements without using javascript. Often, we want the response from
// a turbo frame or stream to contain a modal that is loaded opened.
// This controller handles that.
//
// We used to used to do auto opening in application.js using dom loaded events,
// but there is no similar event for turbo streams (yet, there might be in the future).
//

import "@popperjs/core"; // must come before bootstrap
import "bootstrap"; // see https://github.com/twbs/bootstrap/tree/main/js/src
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["modal", "offcanvas", "tooltip", "form"];
  static values = {
    modalParam: { type: String, default: "modal_context" },
  };

  // adds modal_context parameter to forms, but only
  // if an input already exists.
  addModalContextToForms(el) {
    el.querySelectorAll("form").forEach((form) => {
      const existingInput = form.querySelector(
        `input[name="${this.modalParamValue}"]`,
      );
      if (existingInput) {
        existingInput.value = "true";
      }
    });
  }

  autoOpen(el, getInstance) {
    if (el.classList.contains("auto-open")) {
      if (el.getAttribute("auto-opened") != "yes") {
        getInstance()?.show();
      }
      el.setAttribute("auto-opened", "yes");
    }
  }

  addTooltips(el) {
    el.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((tooltip) => {
      bootstrap.Tooltip.getOrCreateInstance(tooltip);
    });
  }

  // must be visible
  addFocus(el) {
    el.querySelectorAll("[autofocus]").forEach((input) => {
      input.focus();
    });
  }

  modalTargetConnected(modal) {
    this.addModalContextToForms(modal);
    this.addTooltips(modal);
    this.autoOpen(modal, () => bootstrap.Modal.getOrCreateInstance(modal));
    this.addFocus(modal);
  }

  offcanvasTargetConnected(canvas) {
    this.addModalContextToForms(canvas);
    this.addTooltips(canvas);
    this.autoOpen(canvas, () =>
      bootstrap.Offcanvas.getOrCreateInstance(canvas),
    );
    this.addFocus(canvas);
  }

  tooltipTargetConnected(el) {
    this.addTooltips(el);
  }

  formTargetConnected(form) {
    if (!form.querySelector(`input[name="${this.modalParamValue}"]`)) {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = this.modalParamValue;
      input.value = "true";
      form.appendChild(input);
    }
  }
}
