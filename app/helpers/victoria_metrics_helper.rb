#
# Builds the VictoriaMetrics host chart specifications and produces the
# normalized point rows those charts consume (via the shared VegaChartHelper
# builders and the VictoriaMetrics service).
#
# Every chart is backed by its own dataset named after its chart key, so the
# metrics controller can stream per-chart rows into each mounted Vega view
# independently (unlike the container charts, which share one "chartdata" set).
#
# Scope for now: historical data, hypervisor host only (Conf.metrics_host_instance).
#
module VictoriaMetricsHelper
  include VegaChartHelper

  # Default window shown when no window param is provided.
  DEFAULT_WINDOW = 24.hours

  # Approximate number of points to aim for per series when deriving the query
  # step from a window. Larger windows get a coarser step so the request stays
  # proportional to the window.
  TARGET_POINTS = 200

  #
  # Chart definitions: key, title, builder kind, and the PromQL query/queries.
  # Queries may reference %{instance}, interpolated from the configured host
  # instance at build time.
  #
  METRICS_CHARTS = [
    {
      key: "cpu", title: "CPU Usage", kind: :single, color: "#0d6efd",
      y_title: "%",
      query: <<~PROM
        100 * (1 - avg(rate(node_cpu_seconds_total{instance="%{instance}", job="node", mode="idle"}[5m])))
      PROM
    },
    {
      key: "memory", title: "Memory Usage", kind: :single, color: "#198754",
      y_title: "MB",
      query: <<~PROM
        (node_memory_MemTotal_bytes{instance="%{instance}"} - node_memory_MemAvailable_bytes{instance="%{instance}"}) / 1024 / 1024
      PROM
    },
    {
      key: "disk", title: "Disk Usage", kind: :series, color_field: "series",
      y_title: "GB", stack: false,
      series: [ [ "capacity", "#0dcaf0" ], [ "used", "#fd7e14" ], [ "free", "#198754" ] ],
      queries: [
        <<~PROM,
          node_filesystem_size_bytes{instance="%{instance}", mountpoint="/"} / 1024 / 1024 / 1024
        PROM
        <<~PROM,
          (node_filesystem_size_bytes{instance="%{instance}", mountpoint="/"} - node_filesystem_avail_bytes{instance="%{instance}", mountpoint="/"}) / 1024 / 1024 / 1024
        PROM
        <<~PROM
          node_filesystem_avail_bytes{instance="%{instance}", mountpoint="/"} / 1024 / 1024 / 1024
        PROM
      ]
    },
    {
      key: "network", title: "Network", kind: :series, color_field: "series",
      y_title: "Mbit/s",
      series: [ [ "ingress", "#0d6efd" ], [ "egress", "#198754" ] ],
      queries: [
        <<~PROM,
          rate(node_network_receive_bytes_total{device!~"lo|docker.*|veth.*|br-.*|tailscale.*|virbr.*", instance="%{instance}"}[5m]) * 8 / 1000000
        PROM
        <<~PROM
          rate(node_network_transmit_bytes_total{device!~"lo|docker.*|veth.*|br-.*|tailscale.*|virbr.*", instance="%{instance}"}[5m]) * 8 / 1000000
        PROM
      ]
    }
  ].freeze

  # The hypervisor host instance label used to scope every query.
  def metrics_host_instance
    Conf.metrics_host_instance
  end

  # Hash of chart key => Vega chart spec (initialized with empty data).
  def metrics_charts
    METRICS_CHARTS.to_h { |defn| [ defn[:key], metrics_chart_spec(defn, []) ] }
  end

  #
  # Produce the per-chart point rows for a given window.
  #
  # @return [Hash<String, Array>] chart key => rows (like [{ "time" => ms, "value" => n }]).
  #
  def metrics_points(start_time:, end_time:, step:)
    METRICS_CHARTS.to_h do |defn|
      rows = if defn[:kind] == :series
        multi_series_rows(defn, start_time: start_time, end_time: end_time, step: step)
      else
        service.range(render_query(defn[:query]), start_time: start_time, end_time: end_time, step: step)
      end
      [ defn[:key], rows ]
    end
  end

  # Poll cadence for historical charts, in milliseconds (for the JS interval).
  def metrics_historical_interval_ms
    (historical_duration.to_i * 1000)
  end

  #
  # Query step for a given window, as a Prometheus duration string (e.g. "432s").
  # Derived from the window so the number of points per series stays roughly
  # constant regardless of how large a window is requested.
  #
  def metrics_historical_step(window)
    seconds = [ (window.to_i / TARGET_POINTS), 1 ].max
    "#{seconds}s"
  end

  #
  # Resolve the requested chart window (a duration string like "24 hours",
  # "7 days", "30 days"). Defaults to 24 hours and clamps to the historical
  # maximum window so a user can never request more than is retained.
  #
  # @return [ActiveSupport::Duration]
  #
  def metrics_window(window_param = nil)
    requested = window_param.present? ? words_to_time(window_param.to_s) : DEFAULT_WINDOW
    [ requested, metrics_historical_max_duration ].min
  end

  private

  def service
    @service ||= VictoriaMetrics.new
  end

  # Maximum historical window, from Conf.metrics_historical_max_window (90 days).
  def metrics_historical_max_duration
    words_to_time(Conf.metrics_historical_max_window || "90 days")
  end

  # Parses a human duration string like "1 minute" / "30 seconds" / "2 hours"
  # into an ActiveSupport::Duration. Raises ArgumentError for unsupported text.
  def words_to_time(str)
    raise ArgumentError unless str =~ /\A[0-9]+ (seconds?|minutes?|hours?|days?|weeks?|months?|years?)\z/
    str.split.inject { |count, unit| count.to_i.send(unit) }
  end

  # Duration for a single historical poll, from Conf.metrics_historical_interval
  # (1 minute default). Accepts a words string or an integer number of seconds.
  def historical_duration
    value = Conf.metrics_historical_interval || "1 minute"
    value.is_a?(Integer) ? value.seconds : words_to_time(value.to_s)
  end

  def render_query(query)
    format(query, instance: metrics_host_instance)
  end

  # Combine the results of multiple queries into one row list, tagging each row
  # with its series label so the chart can color by the "series" field.
  def multi_series_rows(defn, start_time:, end_time:, step:)
    defn[:series].each_with_index.flat_map do |(label, _color), i|
      service.range(render_query(defn[:queries][i]), start_time: start_time, end_time: end_time, step: step)
              .map { |row| row.merge("series" => label) }
    end
  end

  def metrics_chart_spec(defn, points)
    case defn[:kind]
    when :series
      vega_series_area_spec(points,
        title: defn[:title],
        y_field: "value",
        y_title: defn[:y_title],
        color_field: defn[:color_field],
        domain: defn[:series].map(&:first),
        range: defn[:series].map(&:last),
        stack: defn.fetch(:stack, true),
        tooltip: [
          { field: "time", type: "temporal", title: "Time", format: "%H:%M:%S" },
          { field: "series", type: "nominal", title: "Direction" },
          { field: "value", type: "quantitative", title: defn[:title], format: ".2f" }
        ],
        data_name: defn[:key])
    else
      vega_area_spec(points,
        title: defn[:title],
        y_field: "value",
        y_title: defn[:y_title],
        color: defn[:color],
        tooltip: [
          { field: "time", type: "temporal", title: "Time", format: "%H:%M:%S" },
          { field: "value", type: "quantitative", title: defn[:title], format: ".2f" }
        ],
        data_name: defn[:key])
    end
  end
end
