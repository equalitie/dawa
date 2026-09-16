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
    rendered_window = helpers.metrics_window(window)
    end_time = Time.current
    render json: {
      points: helpers.metrics_points(
        window_token: window,
        start_time: end_time - rendered_window,
        end_time: end_time,
        step: helpers.metrics_historical_step(window)
      )
    }
  end
end
