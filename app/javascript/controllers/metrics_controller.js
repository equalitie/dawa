import VegaChartsController from "controllers/vega_charts_controller";

//
// Streams VictoriaMetrics host metrics into Vega charts.
//
// The server renders each chart's Vega-Lite spec with empty data; the charts
// then poll the metrics JSON endpoint and stream points in. Unlike the
// container charts (which share one "chartdata" dataset), each metric chart is
// backed by its own dataset named after its chart key, so the endpoint returns
// { points: { <chartKey>: [rows...], ... } } and we stream each into its own
// mounted view.
//
// usage:
//   <div data-controller="metrics"
//        data-metrics-url-value="/metrics/data.json"
//        data-metrics-interval-value="60000">
//     <div data-metrics-target="chart"
//          data-chart-key="cpu"
//          data-chart-spec="{...}"></div>
//     ...
//   </div>
//
export default class extends VegaChartsController {
  //
  // Ask only for the charts this page rendered (passed to the stimulus controller as `data-chart-key`)
  //
  pollUrl() {
    const keys = this.chartKeys();
    if (!keys.length) return this.urlValue;

    const url = new URL(this.urlValue, window.location.origin);
    // Repeated `charts[]=a&charts[]=b`: Rails parses that as an array without needing JSON.
    url.searchParams.delete("charts[]");
    keys.forEach((key) => url.searchParams.append("charts[]", key));
    return url.toString();
  }

  handleData(data) {
    const points = data.points || {};
    Object.entries(points).forEach(([key, rows]) => {
      const view = this.views[key];
      if (!view) return;
      try {
        const changeset = this.buildChangeset(rows || []);
        view.change(key, changeset).runAsync();
      } catch (_e) {
        // view may not be fully initialized yet; will retry on next poll
      }
    });
  }
}
