import { Controller } from "@hotwired/stimulus";

//
// Shared Stimulus controller for streaming live data into Vega area charts.
//
// Embedding waits for that first payload because the server renders each spec with
// an empty dataset, and an empty dataset leaves the scales without an extent.
//
// Concrete controllers (e.g. metrics, container-stats) subclass this and override
// #datasetName(key), #rowsFor(key) and (when the server renders no rows) #embedRows.
//
export default class extends Controller {
  static targets = ["chart"];

  static values = {
    url: String,
    interval: { type: Number, default: 1500 },
  };

  connect() {
    this.views = {}; // chartKey -> vega view
    this.points = [];
    this.polling = false;
    this.abortController = null;
    this.embedded = false;

    this.poller = setInterval(() => this.poll(), this.intervalValue);
    this.poll(); // immediate first load
  }

  disconnect() {
    if (this.poller) clearInterval(this.poller);
    this.poller = null;
    // Abort any in-flight request so it can't resolve into a detached chart.
    if (this.abortController) this.abortController.abort();
    this.abortController = null;
    this.polling = false;
    // finalize views to stop their animation loops
    Object.values(this.views).forEach((view) => view && view.finalize());
    this.views = {};
  }

  // The dataset name a chart's rows are streamed into.
  datasetName(key) {
    return "chartdata";
  }

  // The rows for a chart key from the instance's current payload.
  rowsFor(key) {
    return [];
  }

  //
  // The rows to embed a chart with, when its spec carries none.
  //
  embedRows(key, spec) {
    return this.rowsFor(key);
  }

  //
  // Embed each chart with its payload baked in.
  //
  embedCharts() {
    if (this.embedded) return;
    if (typeof window.vegaEmbed !== "function") return;
    this.embedded = true;

    this.chartTargets.forEach((el) => {
      let spec;
      try {
        spec = JSON.parse(el.dataset.chartSpec);
      } catch (_e) {
        return; // invalid spec; skip
      }
      const key = el.dataset.chartKey;
      const body = el.querySelector("[data-chart-body]");
      if (!body) return;

      const name = this.datasetName(key);
      spec.data = Object.assign({}, spec.data, { name });
      if (!Array.isArray(spec.data.values) || spec.data.values.length === 0) {
        spec.data.values = this.embedRows(key, spec);
      }

      window
        .vegaEmbed(body, spec, { actions: false })
        .then((result) => {
          this.views[key] = result.view;
        })
        .catch((err) => {
          console.error("vega embed failed", key, err);
        });
    });
  }

  async poll() {
    // Skip if a request is already in flight (avoids rounding up)
    if (this.polling) return;
    this.polling = true;
    const controller = new AbortController();
    this.abortController = controller;
    try {
      const res = await fetch(this.pollUrl(), {
        headers: { Accept: "application/json" },
        signal: controller.signal,
      });
      if (!res.ok) return;
      const data = await res.json();
      if (this.polling === false) return; // disconnected while awaiting
      this.handleData(data);
    } catch (_e) {
      // transient error or aborted; keep last known points
    } finally {
      this.polling = false;
      if (this.abortController === controller) this.abortController = null;
    }
  }

  //
  // The URL to poll. Can be overridden.
  //
  pollUrl() {
    return this.urlValue;
  }

  //
  // The chart keys this instance is rendering, in DOM order.
  //
  // Take `data-chart-key` on each chart target to determine which charts to grab data for.
  //
  chartKeys() {
    return this.chartTargets
      .map((el) => el.dataset.chartKey)
      .filter((key) => key);
  }

  //
  // Process a polled payload. By default the endpoint returns a full points
  // array (the server trims/serves the window), so we swap the whole dataset
  // and stream it to the charts. Subclasses can override to reshape into {
  // points } then call super or stream manually.
  //
  // The first payload is the one the charts embed with. Later ones are streamed.
  //
  handleData(data) {
    this.points = data.points || this.points;
    if (!this.embedded) {
      this.embedCharts();
    } else {
      this.streamToCharts();
    }
  }

  streamToCharts() {
    this.chartTargets.forEach((el) => {
      const key = el.dataset.chartKey;
      const view = this.views[key];
      if (!view) return;
      try {
        view
          .change(this.datasetName(key), this.buildChangeset(this.rowsFor(key)))
          .runAsync();
      } catch (_e) {
        // view may not be fully initialized yet; skip
      }
    });
  }

  // Replaces the whole dataset with the latest points.
  // view.change requires a changeset, not a raw array.
  buildChangeset(points) {
    const cs = window.vega.changeset().remove(() => true);
    if (points.length) cs.insert(points);
    return cs;
  }
}
