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
    @metrics_charts = helpers.metrics_charts(params[:window])
    @metrics_poll_interval_ms = helpers.metrics_historical_interval_ms
  end

  def data
    end_time = Time.current
    window = helpers.metrics_window(params[:window])
    render json: {
      points: helpers.metrics_points(
        start_time: end_time - window,
        end_time: end_time,
        step: helpers.metrics_historical_step(window)
      )
    }
  end
end
