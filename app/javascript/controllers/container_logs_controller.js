import { Controller } from "@hotwired/stimulus";
import { createConsumer } from "@rails/actioncable";

//
// Subscribes to the ContainerLogsChannel for a container and appends log
// lines to a terminal-styled monitor element as they stream in.
//
// usage:
//   <div data-controller="container-logs"
//        data-container-logs-container-id-value="abc123">
//     <button data-action="container-logs#copy">Copy</button>
//     <button data-action="container-logs#clear">Clear</button>
//     <div data-container-logs-target="monitor" id="container-logs-abc123"></div>
//   </div>
//
export default class extends Controller {
  static targets = ["monitor"];

  static values = {
    containerId: String,
  };

  connect() {
    if (!this.hasMonitorTarget) {
      console.error("[container-logs] NO monitor target found");
      return;
    }

    this.singletonConsumer = this.singletonConsumer || createConsumer();
    this.subscription = this.singletonConsumer.subscriptions.create(
      {
        channel: "ContainerLogsChannel",
        id: this.containerIdValue,
      },
      {
        connected: () => this.resetPrompt(),
        disconnected: () => {},
        rejected: () => {},
        received: (data) => this.appendLines(data),
      },
    );
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe();
    this.subscription = null;
  }

  resetPrompt() {
    if (!this.hasMonitorTarget) return;
    const prompt = this.monitorTarget.querySelector(".container-log-prompt");
    if (prompt) prompt.remove();
  }

  appendLines(data) {
    if (!data || !this.hasMonitorTarget) return;
    this.resetPrompt();
    const lines = Array.isArray(data.lines) ? data.lines : [];
    for (const line of lines) {
      const node = document.createElement("div");
      node.className = "container-log-line";
      node.textContent = line;
      this.monitorTarget.appendChild(node);
    }
    // keep the newest lines in view
    this.monitorTarget.scrollTop = this.monitorTarget.scrollHeight;
  }

  //
  // Clears all currently displayed log lines.
  //
  clear() {
    if (!this.hasMonitorTarget) return;
    this.monitorTarget.textContent = "";
  }
}
