import VegaChartsController from "controllers/vega_charts_controller";

//
// Streams container resource-usage data into live Vega area charts.
//
// Thin subclass of the shared VegaChartsController: the endpoint returns { points: [...] }
// (a flat array) and every chart streams into the one shared "chartdata" dataset, which is
// what #datasetName and #rowsFor default to.
//
// If we never end up implementing any changes for ContainerStatsController
// from VegaChartsController then this subclass can go away.
export default class extends VegaChartsController {
  rowsFor(_key) {
    return this.points || [];
  }
}
