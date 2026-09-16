import VegaChartsController from "controllers/vega_charts_controller";

//
// Streams container resource-usage data into live Vega area charts.
//
// Thin subclass of the shared VegaChartsController. All embed/stream/poll
// behavior is inherited; the endpoint returns { points: [...] } which the
// shared controller handles by default.
//
// If we never end up implementing any changes for ContainerStatsController
// from VegaChartsController then this subclass can go away.
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
export default class extends VegaChartsController {}
