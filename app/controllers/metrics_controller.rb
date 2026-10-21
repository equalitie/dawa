#
# Host metrics dashboard backed by VictoriaMetrics.
#
# `show` renders the Vega chart specs; the metrics Stimulus controller then
# polls `data` (JSON), which returns normalized per-chart point rows computed
# from VictoriaMetrics via the VictoriaMetrics service.
#
class MetricsController < BaseAdminController
  def show
    params[:window] ||= "day"
    @window = params[:window]
    # Which charts a page offers comes from the definitions' target, so this action and
    # AppsController#show_metrics cannot drift apart from the catalogue.
    keys = query_filter ? helpers.app_chart_names : helpers.host_chart_names
    @metrics_charts = helpers.define_charts(keys: keys, window: @window, filter: query_filter)
    @metrics_poll_interval_ms = helpers.metrics_historical_interval_ms
  end

  #
  # this is the JSON chart data response polled by the charts stimulus controller
  #
  def data
    window = params[:window] || "day"
    # Query the most recent grid-aligned window (advancing with real time), so the newest
    # completed step creeps in on each poll. The chart axis auto-spans these points, so both
    # edges stay flush as the window slides forward.
    start_time, end_time = helpers.metrics_query_bounds(window)
    render json: {
      points: helpers.metrics_points(
        keys: requested_chart_keys,
        window_token: window,
        start_time: start_time,
        end_time: end_time,
        step: helpers.metrics_historical_step(window),
        filter: query_filter
      )
    }
  end

  private

  #
  # some params are passed through to the victoriametrics query.
  #
  def query_filter
    params[:dc_inst].present? ? { dc_inst: params[:dc_inst] } : nil
  end

  #
  # The chart keys the client asked for, filtered to the ones this request can serve.
  #
  def requested_chart_keys
    requested = Array(params[:charts]).map(&:to_s).map(&:strip).reject(&:empty?)
    allowed = helpers.chart_definition_names & requested
    allowed
  end
end
