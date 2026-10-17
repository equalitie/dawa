#
# Host metrics dashboard backed by VictoriaMetrics.
#
# `show` renders the Vega chart specs; the metrics Stimulus controller then
# polls `data` (JSON), which returns normalized per-chart point rows computed
# from VictoriaMetrics via the VictoriaMetrics service.
#
class MetricsController < BaseAdminController
  HOST_CHARTS = %w[host_cpu host_memory host_disk host_network].freeze

  def show
    params[:window] ||= "day"
    @window = params[:window]
    @metrics_charts = helpers.define_charts(keys: HOST_CHARTS, window: @window)
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
        step: helpers.metrics_historical_step(window)
      )
    }
  end

  private

  #
  # The chart keys the client asked for, filtered to the ones this dashboard knows.
  #
  def requested_chart_keys
    requested = Array(params[:charts]).map(&:to_s).map(&:strip).reject(&:empty?)
    allowed = HOST_CHARTS & requested
    allowed.presence || HOST_CHARTS
  end
end
