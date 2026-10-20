import VegaChartsController from "controllers/vega_charts_controller";

//
// Streams VictoriaMetrics metrics into Vega charts.
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

  // Each chart streams into a dataset named after its key.
  datasetName(key) {
    return key;
  }

  // The payload is keyed by chart key (handleData stores data.points), so each chart reads
  // its own rows.
  rowsFor(key) {
    return (this.points && this.points[key]) || [];
  }
}
