//
// Stimulus controller for an autocomplete dropdown.
//
// The controller is attached to a div that wraps a button (typically
// rendered by AutocompleteButtonComponent). Clicking the button triggers
// a GET fetch to the URL configured via `data-autocomplete-url-value`.
// The response must be HTML where each selectable option has a
// `data-value` attribute (configurable via `choiceAttributeValue`).
//
// On selection, a hidden input with the chosen value is appended to the
// nearest form (or a specific `data-autocomplete-target="form"` element)
// and the form is submitted. The submitted parameter name is set by
// `data-autocomplete-submit-name-value`.
//
// Usage (outside of AutocompleteButtonComponent):
//
//   <form url="/submit" method="post">
//     <div data-controller="autocomplete"
//        data-autocomplete-url-value="/path/to/choices"
//        data-autocomplete-submit-name-value="some_param_name">
//       <button data-action="click->autocomplete#open">Select...</button>
//     </div>
//   </form>
//
// The server response for the URL should be HTML like:
//
//   <div class="autcomplete-choice" data-value="1">Option One</div>
//   <div class="autcomplete-choice" data-value="2">Option Two</div>
//
// If you need extra content (e.g. a search icon) inside the overlay
// before the input, add a template target:
//
//   <div class="d-none" data-autocomplete-target="template">
//     <span class="input-group-text">🔍</span>
//   </div>
//
// Options:
//   - data-autocomplete-url-value          (required) URL to fetch choices from
//   - data-autocomplete-submit-name-value   (required) param name for the selected value
//   - data-autocomplete-submit-on-select-value  (default: true) whether to submit on selection
//   - data-autocomplete-choice-attribute-value  (default: "data-value") attribute to read value from
//   - data-autocomplete-placeholder-value       (default: "Type to filter...")
//   - data-autocomplete-none-value             (default: "No matches found")
//
// Targets:
//   - form:     a specific form element to submit (default: closest form)
//   - template: optional content rendered in the popup above the search field
//   - append:   if present, the appendTarget will get the selected choice
//               appended to it as a child element.
//
import { Controller } from "@hotwired/stimulus";
import util from "util";

export default class extends Controller {
  static targets = ["template", "form", "append"];
  static values = {
    url: String, // url to load the choices from
    submitName: String, // the param name of the selected result when form is submitted
    submitOnSelect: { type: Boolean, default: true },
    choiceAttribute: { type: String, default: "data-value" },
    placeholder: { type: String, default: "Type to filter..." },
    none: { type: String, default: "No matches found" },
  };

  connect() {
    this.options = [];
    this.filteredOptions = [];
    this.selectedIndex = -1;
    this.isOpen = false;
    this.isNavigatingList = false;
    this.currentRequest = null;
    this.overlay = null;
    this.popper = null;

    // Bind methods
    this.handleDocumentClick = this.handleDocumentClick.bind(this);
    this.handleKeydown = this.handleKeydown.bind(this);
    this.handleInput = this.handleInput.bind(this);
    this.handleChoiceClick = this.handleChoiceClick.bind(this);
  }

  disconnect() {
    this.cleanupSignal();
    this.closeOverlay();
  }

  //
  // Public API
  //

  open(event) {
    event?.preventDefault();

    if (this.isOpen) {
      this.closeOverlay();
    }

    this.createSignal();
    this.renderOverlay();
    this.showLoadingState();
    this.fetchChoices();
  }

  close() {
    this.closeOverlay();
  }

  //
  // Private Methods
  //

  // signal management

  get signal() {
    return this.abortController.signal;
  }

  cleanupSignal() {
    if (this.abortController) {
      this.abortController.abort();
      this.abortController = null;
    }
  }

  createSignal() {
    this.cleanupSignal();
    this.abortController = new AbortController();
  }

  // network

  async fetchChoices() {
    // Cancel any in-flight request
    if (this.currentRequest) {
      this.currentRequest.abort();
    }

    this.currentRequest = new AbortController();

    try {
      const response = await fetch(this.urlValue, {
        signal: this.currentRequest.signal,
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest",
        },
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const html = await response.text();

      // Parse and store options
      const temp = document.createElement("div");
      temp.innerHTML = html;
      this.options = Array.from(
        temp.querySelectorAll(`[${this.choiceAttributeValue}]`),
      );
      this.originalHtml = html;
      this.filterOptions();
    } catch (error) {
      if (error.name !== "AbortError") {
        console.error("Failed to fetch choices:", error);
        this.showErrorState();
      }
    } finally {
      this.currentRequest = null;
    }
  }

  //
  // UI
  //

  renderOverlay() {
    // Create overlay container
    this.overlay = document.createElement("div");
    this.overlay.className =
      "autocomplete-overlay border shadow rounded bg-white";
    this.overlay.setAttribute("role", "presentation");

    // Create popover content
    this.overlay.innerHTML = `
      <div class="autocomplete-container">
        <div class="autocomplete-header p-2 border-bottom">
          <input type="text"
            class="form-control autocomplete-input"
            placeholder="${this.placeholderValue}"
            autocomplete="off"
            role="combobox"
            aria-autocomplete="list"
            aria-controls="autocomplete-list"
            aria-expanded="true">
        </div>
        <div class="autocomplete-list-wrapper"">
          <div class="autocomplete-list" id="autocomplete-list" role="listbox"></div>
        </div>
      </div>
    `;

    if (this.hasTemplateTarget) {
      const input = this.overlay.querySelector("input");
      const template = this.templateTarget.cloneNode(true);
      template.classList.remove("d-none");
      input.parentNode.insertBefore(template, input);
    }

    document.body.appendChild(this.overlay);

    this.popper = Popper.createPopper(this.element, this.overlay, {
      placement: "bottom-start",
      modifiers: [
        {
          name: "offset",
          options: {
            offset: [0, 8], // [skid, distance] from element
          },
        },
        {
          name: "flip",
          options: {
            fallbackPlacements: ["top-start", "bottom-start"],
          },
        },
        {
          name: "preventOverflow",
          options: {
            padding: 8,
          },
        },
      ],
    });

    // Show the overlay
    this.overlay.style.display = "block";
    this.popper.update();

    // Get references to elements
    this.inputElement = this.overlay.querySelector(".autocomplete-input");
    this.listElement = this.overlay.querySelector(".autocomplete-list");
    this.loadingIndicator = this.overlay.querySelector(".autocomplete-loading");

    // Setup event listeners
    this.inputElement.addEventListener("input", this.handleInput, {
      signal: this.signal,
    });
    this.listElement.addEventListener("click", this.handleChoiceClick, {
      signal: this.signal,
    });

    // Setup global listeners
    this.setupGlobalListeners();

    // Focus the input
    setTimeout(() => {
      this.inputElement.focus();
      this.inputElement.select();
    }, 0);

    this.isOpen = true;

    util.announce(
      "Options loaded. Use arrow keys to navigate, Enter to select.",
    );
  }

  showLoadingIndicator() {
    return !this.options.length && !this.originalHtml;
  }

  setupGlobalListeners() {
    document.addEventListener("click", this.handleDocumentClick, {
      signal: this.signal,
    });
    document.addEventListener("keydown", this.handleKeydown, {
      signal: this.signal,
    });
    window.addEventListener("scroll", () => this.popper?.update(), {
      signal: this.signal,
    });
    window.addEventListener("resize", () => this.popper?.update(), {
      signal: this.signal,
    });
  }

  handleInput() {
    this.isNavigatingList = false;
    this.filterOptions();
  }

  filterOptions() {
    const searchTerm = this.inputElement.value.toLowerCase();

    // Filter options
    this.filteredOptions = searchTerm
      ? this.options.filter((option) => {
          const text = option.textContent.toLowerCase();
          return text.includes(searchTerm);
        })
      : [...this.options];

    this.renderFilteredList(this.filteredOptions);

    // Reset and select first option if available
    this.selectedIndex = this.filteredOptions.length > 0 ? 0 : -1;
    this.updateSelectedHighlight();
  }

  renderFilteredList(options) {
    if (!this.listElement) return;

    if (options.length === 0) {
      this.listElement.innerHTML = `
        <div class="text-muted p-2 text-center" role="status">
          ${this.noneValue}
        </div>
      `;
      return;
    }

    const html = options
      .map((option, index) => {
        const originalHtml = option.outerHTML;
        if (this.inputElement.value) {
          const searchTerm = this.inputElement.value;
          const text = option.textContent;
          const regex = new RegExp(`(${util.escapeRegex(searchTerm)})`, "gi");
          const highlightedText = text.replace(
            regex,
            '<mark class="autocomplete-highlight">$1</mark>',
          );
          return originalHtml.replace(option.textContent, highlightedText);
        }
        return originalHtml;
      })
      .join("");

    this.listElement.innerHTML = html;

    // Add ARIA attributes to options
    const items = this.listElement.querySelectorAll(
      `[${this.choiceAttributeValue}]`,
    );
    items.forEach((item, idx) => {
      item.setAttribute("role", "option");
      item.setAttribute("aria-selected", "false");
      item.id = `autocomplete-option-${idx}`;
    });

    // Update popper position after content changes
    this.popper?.update();
  }

  handleKeydown(event) {
    if (!this.isOpen) return;

    const keyHandlers = {
      ArrowDown: () => {
        event.preventDefault();
        this.moveToNextOption();
        this.isNavigatingList = true;
      },
      ArrowUp: () => {
        event.preventDefault();
        this.moveToPreviousOption();
        this.isNavigatingList = true;
      },
      Enter: () => {
        if (this.isNavigatingList || this.selectedIndex !== -1) {
          event.preventDefault();
          this.selectCurrentOption();
        }
      },
      Escape: () => {
        this.closeOverlay();
      },
    };

    const handler = keyHandlers[event.key];
    if (handler) handler();
  }

  handleDocumentClick(event) {
    if (!this.isOpen) return;

    const isClickInside =
      this.overlay?.contains(event.target) ||
      this.element.contains(event.target);

    if (!isClickInside) {
      this.closeOverlay();
    }
  }

  handleChoiceClick(event) {
    const choice = event.target.closest(`[${this.choiceAttributeValue}]`);
    if (choice) {
      const value = choice.getAttribute(this.choiceAttributeValue);
      this.selectValue(value, choice.textContent);
    }
  }

  moveToNextOption() {
    if (this.filteredOptions.length === 0) return;

    this.selectedIndex = (this.selectedIndex + 1) % this.filteredOptions.length;
    this.updateSelectedHighlight();
    this.scrollToSelectedOption();
  }

  moveToPreviousOption() {
    if (this.filteredOptions.length === 0) return;

    this.selectedIndex = this.selectedIndex - 1;
    if (this.selectedIndex < 0) {
      this.selectedIndex = this.filteredOptions.length - 1;
    }
    this.updateSelectedHighlight();
    this.scrollToSelectedOption();
  }

  scrollToSelectedOption() {
    const selectedElement = this.getSelectedOptionElement();
    if (selectedElement && this.listElement) {
      const container = this.listElement.closest(".autocomplete-list-wrapper");
      if (container) {
        const elementTop = selectedElement.offsetTop;
        const elementBottom = elementTop + selectedElement.offsetHeight;
        const containerTop = container.scrollTop;
        const containerBottom = containerTop + container.clientHeight;

        if (elementTop < containerTop) {
          container.scrollTop = elementTop;
        } else if (elementBottom > containerBottom) {
          container.scrollTop = elementBottom - container.clientHeight;
        }
      }
    }
  }

  updateSelectedHighlight() {
    const options = this.listElement?.querySelectorAll(
      `[${this.choiceAttributeValue}]`,
    );
    if (!options) return;

    options.forEach((option, index) => {
      const isSelected = index === this.selectedIndex;
      option.classList.toggle("active", isSelected);
      option.classList.toggle("bg-primary", isSelected);
      option.classList.toggle("text-white", isSelected);
      option.setAttribute("aria-selected", isSelected ? "true" : "false");
      if (isSelected) {
        option.id = "autocomplete-active-option";
      }
    });

    // Update aria-activedescendant on input
    if (this.inputElement && this.selectedIndex !== -1) {
      this.inputElement.setAttribute(
        "aria-activedescendant",
        `autocomplete-option-${this.selectedIndex}`,
      );
    } else if (this.inputElement) {
      this.inputElement.removeAttribute("aria-activedescendant");
    }
  }

  getSelectedOptionElement() {
    const options = this.listElement?.querySelectorAll(
      `[${this.choiceAttributeValue}]`,
    );
    return options?.[this.selectedIndex];
  }

  selectCurrentOption() {
    const selectedOption = this.getSelectedOptionElement();
    if (selectedOption) {
      const value = selectedOption.getAttribute(this.choiceAttributeValue);
      this.selectValue(value, selectedOption.textContent);
    }
  }

  selectValue(value, displayText) {
    util.announce(`Selected ${displayText}`);
    const form = this.hasFormTarget
      ? this.formTarget
      : this.element.closest("form");
    if (form) {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = this.submitNameValue;
      input.value = value;
      form.appendChild(input);
      if (this.submitOnSelectValue) {
        util.submitForm(form);
      } else if (this.hasAppendTarget) {
        const div = document.createElement("div");
        div.innerText = displayText;
        this.appendTarget.appendChild(div);
      }
    }
    this.closeOverlay();
  }

  closeOverlay() {
    if (this.overlay) {
      this.overlay.remove();
      this.overlay = null;
    }

    if (this.popper) {
      this.popper.destroy();
      this.popper = null;
    }

    if (this.inputElement) {
      this.inputElement.value = "";
    }

    this.inputElement = null;
    this.listElement = null;
    this.isOpen = false;
    this.isNavigatingList = false;
    this.selectedIndex = -1;

    this.element.focus();
  }

  showLoadingState() {
    if (this.overlay && this.listElement) {
      this.listElement.innerHTML = `
        <div class="text-muted p-2 text-center">
          <div class="spinner-border spinner-border-sm me-2" role="status">
            <span class="visually-hidden">Loading...</span>
          </div>
        </div>
      `;
    }
  }

  showErrorState() {
    if (this.overlay && this.listElement) {
      this.listElement.innerHTML = `
        <div class="text-danger p-2 text-center">
          Failed to load options. Please try again.
        </div>
      `;

      setTimeout(() => {
        if (this.isOpen) this.closeOverlay();
      }, 2000);
    } else {
      console.error("Failed to load autocomplete options");
    }
  }
}
