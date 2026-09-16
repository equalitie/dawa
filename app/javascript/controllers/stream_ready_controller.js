//
// disables ui elements until the turbo stream is ready
//

import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button"];
  static values = {
    pollInterval: { type: Number, default: 500 },
    streamId: { type: String, default: "" },
  };

  connect() {
    this.connected = false;
    this.observer = null;
    this.pollTimer = null;
    this.source = null;
    this.setupDetection();
  }

  buttonTargetConnected(element) {
    element.disabled = !this.connected;
  }

  disconnect() {
    if (this.observer) this.observer.disconnect();
    if (this.pollTimer) clearInterval(this.pollTimer);
  }

  findSource() {
    if (this.sourceIdValue) {
      this.source = document.getElementById(this.streamIdValue);
    } else {
      this.source = document.querySelector("turbo-cable-stream-source");
    }
  }

  setupDetection() {
    // Check initial state
    this.checkConnection();

    // Watch for changes to the 'connected' attribute
    this.observer = new MutationObserver(() => {
      this.checkConnection();
    });
    this.observer.observe(this.source, {
      attributes: true,
      attributeFilter: ["connected"],
    });

    // Fallback polling (in case MutationObserver misses changes)
    this.pollTimer = setInterval(() => {
      this.checkConnection();
    }, this.pollIntervalValue);
  }

  checkConnection() {
    this.findSource();
    const isConnected = this.source.hasAttribute("connected");
    if (isConnected !== this.connected) {
      this.setConnected(isConnected);
    }
  }

  setConnected(connected) {
    this.connected = connected;
    this.updateButtons();
  }

  updateButtons() {
    this.buttonTargets.forEach((button) => {
      if (
        button.tagName === "BUTTON" ||
        (button.tagName === "INPUT" && button.type === "submit")
      ) {
        button.disabled = !this.connected;
      }
    });
  }
}
