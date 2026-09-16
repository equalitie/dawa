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
    @metrics_charts = helpers.metrics_charts(@window)
    @metrics_poll_interval_ms = helpers.metrics_historical_interval_ms
  end

  def data
    window = params[:window] || "day"
    # Query the most recent grid-aligned window (advancing with real time), so the newest
    # completed step creeps in on each poll. The chart axis auto-spans these points, so both
    # edges stay flush as the window slides forward.
    start_time, end_time = helpers.metrics_query_bounds(window)
    render json: {
      points: helpers.metrics_points(
        window_token: window,
        start_time: start_time,
        end_time: end_time,
        step: helpers.metrics_historical_step(window)
      )
    }
  end
end
