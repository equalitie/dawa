#
# Builds chart specs and point rows for the VictoriaMetrics host dashboard. It turns the
# pure graph definitions in chart_definitions.rb into:
#
#   * Vega chart specs rendered on page load (define_charts),
#   * per-chart point rows fetched on each poll (metrics_points).
#
#
module Metrics::VictoriametricsHelper
  include Metrics::ChartDefinitions
  include Metrics::VegaHelper

  # Default window token shown when none is provided.
  DEFAULT_WINDOW = "day"

  # window token => window range (aka the duration over which a single graph point is averaged)
  #
  # Choosing the range equal to one sample-advance means
  # consecutive points tile the window with no gaps, and roughly:
  #
  #   day(24h)/5m  = 288 pts
  #   week(7d)/30m = 336 pts
  #   month(30d)/2h = 360 pts
  #   quarter(90d)/6h = 360 pts
  #
  WINDOW_RANGES = {
    "day"     => "5m",
    "week"    => "30m",
    "month"   => "2h",
    "quarter" => "6h"
  }.freeze

  def define_charts(keys:, window:)
    keys.to_h {|key|
      [ key, define_chart(key: key, window: window) ]
    }.compact
  end

  #
  # key - chart definition key
  # window - a window token (e.g. week)
  #
  def define_chart(key:, window:)
    defn = chart_definition(key)
    if defn
      metrics_chart_spec(key, defn, [], range: window_range(window))
    end
  end

  #def host_charts
  #  CHARTS.slice("host_cpu", "host_memory", "host_disk", "host_network")
  #end

  # returns hash of Chart key => Vega chart spec.
  #
  #def metrics_charts(window_token = DEFAULT_WINDOW)
  #  token = normalize_window_token(window_token)
  #  host_charts.to_h { |key, defn|
  #    [ key, metrics_chart_spec(key, defn, [], range: window_range(token)) ]
  #  }
  #end

  # Millisecond-epoch x-domain [start, end] for the window denoted by window_token.
  # Both edges snap to the per-point sample grid (the window spans a whole number of
  # steps), so the first and newest streamed samples land flush against the frame edges.
  # This is the same reference `data` queries against, keeping the axis and cells aligned.
  def metrics_time_domain(window_token = DEFAULT_WINDOW, now: Time.current)
    start_s, end_s = metrics_sample_window(normalize_window_token(window_token), now: now)
    [ start_s * 1000, end_s * 1000 ]
  end

  #
  # Epoch-second [start, end] bounds (as Times) for window_token, grid-aligned to whole
  # sample steps ending at the newest completed step at/before `now`. The data endpoint
  # passes these straight to the VictoriaMetrics query so the latest returned sample lands
  # exactly on the chart's right-hand axis edge (with no variable-width trailing gap from
  # a window that ends mid-step on wall-clock "now").
  #
  def metrics_query_bounds(window_token = DEFAULT_WINDOW, now: Time.current)
    start_s, end_s = metrics_sample_window(normalize_window_token(window_token), now: now)
    [ Time.at(start_s), Time.at(end_s) ]
  end

  #
  # Fetch point rows for every requested chart in the current window.
  #
  # `keys` is the same list the page passed to `define_charts`, so the endpoint queries exactly the
  # charts that were rendered. Without it the endpoint has no way to know which charts exist: there
  # is no "current dashboard" global, and querying every definition would spend the expensive
  # VictoriaMetrics calls on charts nobody is looking at.
  #
  # @return [Hash<String, Array>] chart key => rows (like [{ "time" => ms, "value" => n }]).
  #
  def metrics_points(keys:, window_token: DEFAULT_WINDOW, start_time:, end_time:, step: nil)
    token = normalize_window_token(window_token)
    range = window_range(token)
    step ||= "#{range_to_seconds(range)}s"
    step_seconds = range_to_seconds(range) # per-point bucket width, authoritative for tiling
    keys.to_h do |key|
      defn = chart_definition(key)
      # A key with no definition would otherwise raise deep inside the query build, after the
      # other charts' queries had already run. Skipping it keeps the rest of the dashboard alive.
      if defn.nil?
        Log.write(:warn, "metrics chart has no definition", key)
        next [ key, [] ]
      end

      rows = if multi_series?(defn)
        multi_series_rows(defn, range: range, start_time: start_time, end_time: end_time, step: step)
      else
        service.range(render_query(defn[:query], range), start_time: start_time, end_time: end_time, step: step)
      end
      if rows.empty?
        Log.write(:warn, "metrics query returned no samples", key,
          "window", token, "queries", defn[:queries] || defn[:query])
      end
      [ key, pad_missing_points(rows, start_time: start_time, end_time: end_time, step_seconds: step_seconds) ]
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

  #
  # Integer epoch-seconds [start, end] of the window for token, aligned so the width is
  # a whole number of per-point sample steps and `end` is the most recent completed step
  # at/before `now`. Returns integer seconds (not ms) sorted for the query/domain math.
  #
  # @private
  def metrics_sample_window(token, now:)
    step_s  = range_to_seconds(window_range(token))
    win_s   = effective_window_seconds(token)
    n_steps = (win_s.to_f / step_s).round
    end_s   = (now.to_i / step_s) * step_s
    [ end_s - n_steps * step_s, end_s ]
  end

  # Effective window width in seconds, clamped to the retention max (so the tiled domain
  # width always matches what the data endpoint actually queries).
  def effective_window_seconds(token)
    metrics_window(token).to_i
  end

  def normalize_window_token(window_token)
    t = window_token.to_s
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

  #
  # Ensure every sampled slot of the requested window is present in the rows, substituting
  # a null value for slots the backend had no sample for (rather than silently connecting the
  # line/area across a gap). A slot is [..] the window tiled at step_seconds. For multi-series
  # rows (tagged "series") each series is padded independently, since gaps can differ per series.
  #
  # @return [Array<Hash>] rows with complete, ascending coverage; missing slots carry
  #   value_key ("value") = nil so Vega leaves a visible gap instead of interpolating.
  #
  def pad_missing_points(rows, start_time:, end_time:, step_seconds:)
    start_ms = start_time.to_i * 1000
    step_ms  = step_seconds * 1000
    timeline = (0..((end_time.to_i * 1000 - start_ms) / step_ms.to_f).round)
               .map { |i| start_ms + i * step_ms }
    slot = ->(t_any) { (t_any.to_i - start_ms) / step_ms }
    groups = rows.empty? ? { nil => [] } : rows.group_by { |row| row["series"] }

    groups.flat_map do |group, group_rows|
      by_point = group_rows.index_by { |row| slot.call(row["time"]) }
      timeline.map do |t_ms|
        row = by_point[slot.call(t_ms)]
        next row if row
        cursor = { "time" => t_ms, "value" => nil }
        cursor["series"] = group unless group.nil?
        cursor
      end
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
