#
# Builds chart specs and point rows for the VictoriaMetrics host dashboard. It turns the
# pure graph definitions in MetricChartDefinitions into:
#   * Vega chart specs rendered on page load (metrics_charts),
#   * per-chart point rows fetched on each poll (metrics_points).
#
# Chart/definitions live in MetricChartDefinitions (HOST_CHARTS / CONTAINER_CHARTS); this
# module only handles turning a definition into a spec/query and a window token into query
# granularity. Container charts are not implemented yet; this file keeps a hook for them.
#
module VictoriaMetricsHelper
  include VegaChartHelper
  include MetricChartDefinitions

  # Default window token shown when none is provided.
  DEFAULT_WINDOW = "day"

  #
  # Definitions to render on the metrics page: app-facing, merged host charts for now.
  # Container charts will be added here once per-container metrics are wired in.
  #
  def dashboard_charts
    HOST_CHARTS
  end

  # Hash of chart key => Vega chart spec (empty data), with the x-domain pinned to the
  # whole requested window so the axis spans the range even if data doesn't reach back
  # that far. window_token selects both the time range and the per-point aggregation range.
  def metrics_charts(window_token = DEFAULT_WINDOW)
    token = normalize_window_token(window_token)
    time_domain = metrics_time_domain(token)
    dashboard_charts.to_h { |key, defn| [ key, metrics_chart_spec(key, defn, [], range: window_range(token), time_domain: time_domain) ] }
  end

  # Millisecond-epoch x-domain [start, end] for the window denoted by window_token.
  def metrics_time_domain(window_token = DEFAULT_WINDOW)
    token = normalize_window_token(window_token)
    window = window_duration(token)
    ends = Time.current
    [ (ends - window).to_f * 1000, ends.to_f * 1000 ].map(&:to_i)
  end

  #
  # Fetch point rows for every chart in the current window.
  #
  # @return [Hash<String, Array>] chart key => rows (like [{ "time" => ms, "value" => n }]).
  #
  def metrics_points(window_token: DEFAULT_WINDOW, start_time:, end_time:, step: nil)
    token = normalize_window_token(window_token)
    range = window_range(token)
    step ||= "#{range_to_seconds(range)}s"
    dashboard_charts.to_h do |key, defn|
      rows = if multi_series?(defn)
        multi_series_rows(defn, range: range, start_time: start_time, end_time: end_time, step: step)
      else
        service.range(render_query(defn[:query], range), start_time: start_time, end_time: end_time, step: step)
      end
      [ key, rows ]
    end
  end

  # Poll cadence for historical charts, in milliseconds (for the JS interval).
  def metrics_historical_interval_ms
    (historical_duration.to_i * 1000)
  end

  #
  # Query step (Prometheus duration, e.g. "300s") derived from the window token. It equals
  # the per-point aggregation range, so consecutive points tile the window with no gaps.
  #
  def metrics_historical_step(window_token = DEFAULT_WINDOW)
    range = window_range(normalize_window_token(window_token))
    "#{range_to_seconds(range)}s"
  end

  # Per-point aggregation range for a window token, e.g. "5m".
  def window_range(window_token = DEFAULT_WINDOW)
    WINDOW_RANGES.fetch(normalize_window_token(window_token))
  end

  # Resolve the requested window (Duration) for a token, clamped to the retention max.
  def metrics_window(window_token = DEFAULT_WINDOW)
    token = normalize_window_token(window_token)
    [ window_duration(token), metrics_historical_max_duration ].min
  end

  private

  def window_duration(token)
    case token
    when "week" then 7.days
    when "month" then 30.days
    when "quarter" then 90.days
    else 24.hours
    end
  end

  def normalize_window_token(token)
    t = token.to_s
    t = DEFAULT_WINDOW if t.blank?
    WINDOW_RANGES.key?(t) ? t : DEFAULT_WINDOW
  end

  # "5m" => 300 ; "30m" => 1800 ; "2h" => 7200 ; "6h" => 21600
  def range_to_seconds(range)
    unit = range[-1]
    num = range[0...-1].to_i
    case unit
    when "s" then num
    when "m" then num * 60
    when "h" then num * 3600
    when "d" then num * 86_400
    else num
    end
  end

  def multi_series?(defn)
    defn[:kind] == :series
  end

  def metrics_chart_spec(key, defn, points, range:, time_domain: nil)
    if multi_series?(defn)
      vega_series_area_spec(points,
        title: defn[:title],
        y_field: "value",
        y_title: defn[:y_title],
        y_axis_format: defn[:y_axis_format],
        color_field: defn[:color_field],
        domain: defn[:series].map(&:first),
        range: defn[:series].map(&:last),
        stack: defn.fetch(:stack, true),
        tooltip: chart_tooltip(defn, "Metric"),
        data_name: defn.fetch(:data_name, key),
        time_domain: time_domain)
    else
      vega_area_spec(points,
        title: defn[:title],
        y_field: "value",
        y_title: defn[:y_title],
        y_axis_format: defn[:y_axis_format],
        color: defn[:color],
        tooltip: chart_tooltip(defn, nil),
        data_name: defn.fetch(:data_name, key),
        time_domain: time_domain)
    end
  end

  def chart_tooltip(defn, series_title)
    base = [ { field: "time", type: "temporal", title: "Time", format: "%b %d %H:%M" } ]
    base << { field: "series", type: "nominal", title: series_title } if series_title
    base << {
      field: "value", type: "quantitative",
      # label the value with the same unit as the y axis, not the (chart-wide) title
      title: defn[:y_title].presence || defn[:title],
      format: tooltip_value_format(defn)
    }
    base
  end

  # Keep the hover value formatted like the y-axis ticks where a chart pins an integer axis
  # (y_axis_format: "d"), otherwise show the same 2-decimal default as before.
  def tooltip_value_format(defn)
    defn[:y_axis_format].to_s == "d" ? ".0f" : ".2f"
  end

  def render_query(template, range)
    format(template, range: range)
  end

  # Run every series' query, tagging the returned rows with its series label so the chart
  # can stack/color by field.
  def multi_series_rows(defn, range:, start_time:, end_time:, step:)
    defn[:series].each_with_index.flat_map do |(label, _color), i|
      service.range(render_query(defn[:queries][i], range), start_time: start_time, end_time: end_time, step: step)
              .map { |row| row.merge("series" => label) }
    end
  end

  def service
    @service ||= VictoriaMetrics.new
  end

  # Maximum historical window, from Conf.metrics_historical_max_window (90 days).
  def metrics_historical_max_duration
    words_to_time(Conf.metrics_historical_max_window || "90 days")
  end

  def words_to_time(str)
    raise ArgumentError unless str =~ /\A[0-9]+ (seconds?|minutes?|hours?|days?|weeks?|months?|quarters?|years?)\z/
    count, unit = str.split
    n = count.to_i
    case unit
    when "quarter", "quarters" then n.months * 3
    else n.send(unit)
    end
  end

  def historical_duration
    value = Conf.metrics_historical_interval || "1 minute"
    value.is_a?(Integer) ? value.seconds : words_to_time(value.to_s)
  end
end
