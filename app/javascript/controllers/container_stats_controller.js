import { Controller } from "@hotwired/stimulus";

//
// Streams container resource-usage data into live Vega area charts.
//
// The server renders the initial Vega-Lite specs (via vega.rb) as JSON in
// data-chart-spec attributes. This controller embeds each chart once, then
// polls the stats JSON endpoint and streams new points into the mounted
// Vega views with view.change("chartdata", changeset).runAsync() — no full
// chart re-render.
//
// usage:
//   <div data-controller="container-stats"
//        data-container-stats-url-value="/containers/abc/stats.json"
//        data-container-stats-interval-value="1500">
//     <div data-container-stats-target="chart"
//          data-chart-key="cpu"
//          data-chart-spec="{...}"></div>
//     ...
//   </div>
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
    this.embedCharts();

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

  embedCharts() {
    if (typeof window.vegaEmbed !== "function") return;
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
      window
        .vegaEmbed(body, spec, { actions: false })
        .then((result) => {
          this.views[key] = result.view;
        })
        .catch(() => {
          // embed failed; leave the chart area empty
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
      const res = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        signal: controller.signal,
      });
      if (!res.ok) return;
      const data = await res.json();
      if (this.polling === false) return; // disconnected while awaiting
      // The server trims the series to POINTS_WINDOW (15 min), so use it as-is.
      this.points = data.points || this.points;
      this.streamToCharts();
    } catch (_e) {
      // transient error or aborted; keep last known points
    } finally {
      this.polling = false;
      if (this.abortController === controller) this.abortController = null;
    }
  }

  streamToCharts() {
    const changeset = this.buildChangeset(this.points);
    Object.values(this.views).forEach((view) => {
      if (!view) return;
      try {
        view.change("chartdata", changeset).runAsync();
      } catch (_e) {
        // view may not be fully initialized yet; skip
      }
    });
  }

  //
  // Replaces the whole "chartdata" dataset with the latest points.
  // view.change requires a changeset, not a raw array.
  //
  buildChangeset(points) {
    const cs = window.vega.changeset().remove(() => true);
    if (points.length) cs.insert(points);
    return cs;
  }
}
