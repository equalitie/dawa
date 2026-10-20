require "prometheus/api_client"

#
# Thin wrapper around VictoriaMetrics' Prometheus-compatible API, scoped by
# default to the hypervisor host (Conf.metrics_host_instance).
#
# The gem returns the raw matrix/vector payload; this service normalizes it into
# the point-row shape the Vega chart layer consumes: each row is a hash keyed by
# "time" (ms epoch, matching Vega's temporal scale) plus a numeric value field.
#
# Example:
#   VictoriaMetrics.new.range(
#     query: "...",
#     start_time: 1.hour.ago, end_time: Time.current, step: "60s"
#   )
#   # => [{ "time" => 1787518020000, "value" => 7960.28 }, ...]
#
class VictoriaMetrics
  # Default JSON field into which a series' value lands, so charts can map the
  # shared Vega builders onto it (e.g. y_field: "value").
  DEFAULT_VALUE_KEY = "value"

  attr_reader :value_key

  def initialize(url: nil, value_key: DEFAULT_VALUE_KEY, open_timeout: 2, timeout: 10)
    @url = url || Conf.metrics_url
    @value_key = value_key
    @open_timeout = open_timeout
    @timeout = timeout
  end

  # The backend this instance queries. Exposed so a failure can name the host it tried.
  attr_reader :url

  # The instance label that identifies the hypervisor host in VictoriaMetrics.
  def host_instance
    Conf.metrics_host_instance
  end

  #
  # Evaluate a range query and return normalized chart point rows.
  #
  # @return [Array<Hash>] point rows, possibly empty on error/no data. Each row
  #   is { "time" => ms_epoch, value_key => Numeric } joined across series and
  #   ordered by timestamp. A "series" label key is added when more than one
  #   series is returned so callers can tell them apart.
  #
  def range(query, start_time:, end_time:, step:)
    data = client.query_range(query: query, start: ts(start_time), end: ts(end_time), step: step)
    normalize(data)
  rescue Prometheus::ApiClient::Client::RequestError => e
    Log.write(:error, "VictoriaMetrics query_range failed", "url=#{url}", query, e.message)
    []
  end

  #
  # Evaluate an instant query and return current value(s). Returns nil when the
  # expression has no result (good for "current value" display cards).
  #
  # @return [Float, nil] the single instant value, or nil when absent/error.
  #
  def current(query, time: nil)
    data = client.query(query: query, time: (ts(time) if time))
    vector = data.fetch("result", [])
    return nil if vector.empty?
    # For host-scoped queries there is one series; take its value.
    value = vector.first.dig("value", 1)
    value && Float(value)
  rescue Prometheus::ApiClient::Client::RequestError => e
    Log.write(:error, "VictoriaMetrics query failed", "url=#{url}", query, e.message)
    nil
  end

  #
  # Run an instant query and return the raw series list. Unlike #current, which
  # collapses to a single Float, this preserves every series and its metric labels,
  # which is what diagnostics need (e.g. the list of instances a `up` query reports).
  # Raises on connection/timeout errors so callers can distinguish "unreachable"
  # from "reached but no result".
  #
  # @return [Array<Hash>] the vector's "result" array, e.g.
  #   [ { "metric" => { "instance" => "host:9100", "job" => "node" }, "value" => [ts, "1"] }, ... ]
  #
  def vector(query, time: nil)
    data = client.query(query: query, time: (ts(time) if time))
    data.fetch("result", [])
  end

  private

  def client
    @client ||= Prometheus::ApiClient.client(
      url: @url,
      options: { open_timeout: @open_timeout, timeout: @timeout }
    )
  end

  #
  # Turn a matrix (and, defensively, a vector) into point rows. Each series
  # contributes { "time" => ms, value_key => value } rows; values are strings in
  # the API response, so they are converted to Float.
  #
  def normalize(data)
    return [] unless data&.is_a?(Hash)

    result = data.fetch("result", [])
    multiple = result.size > 1
    points = []

    result.each do |series|
      series_label = series.dig("metric", "instance")
      Array(series["values"]).each do |(epoch, raw)|
        next if raw.nil?

        row = { "time" => Integer(epoch.to_f * 1000) }
        row[value_key] = Float(raw)
        row["series"] = series_label if multiple
        points << row
      end
    end

    points.sort_by { |row| row["time"] }
  end

  # Accepts Time, Integer (epoch seconds), or nil; VictoriaMetrics accepts a
  # numeric Unix timestamp, so we pass the seconds through directly.
  def ts(value)
    case value
    when Time then value.to_f
    else value
    end
  end
end
