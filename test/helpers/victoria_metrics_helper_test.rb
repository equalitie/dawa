require "test_helper"

#
# Tests for VictoriaMetricsHelper: chart spec construction, per-point aggregation ranges
# per window, and the per-chart point rows the metrics controller consumes. The VM service
# client is stubbed so these run without a live VictoriaMetrics instance.
#
class VictoriaMetricsHelperTest < ActiveSupport::TestCase
  include VictoriaMetricsHelper

  def stub_range_rows(rows)
    captured = []
    @captured_queries = captured
    payload = { "resultType" => "matrix", "result" => [ { "metric" => {}, "values" => rows } ] }
    fake_client = Object.new
    fake_client.define_singleton_method(:query_range) do |**kw|
      captured << kw[:query]
      payload
    end
    fake_client.define_singleton_method(:query) { |**_kw| { "resultType" => "vector", "result" => [] } }
    stub_service_client(fake_client)
  end

  def stub_service_client(fake_client)
    service = VictoriaMetrics.new
    service.instance_variable_set(:@client, fake_client)
    self.instance_variable_set(:@service, service)
  end

  test "HOST_CHARTS is keyed by id and CONTAINER_CHARTS is empty" do
    assert_equal %w[cpu memory disk network], MetricChartDefinitions::HOST_CHARTS.keys
    assert_empty MetricChartDefinitions::CONTAINER_CHARTS
  end

  test "WINDOW_RANGES maps each window to a point-tiling aggregation range" do
    assert_equal "5m",  MetricChartDefinitions::WINDOW_RANGES["day"]
    assert_equal "30m", MetricChartDefinitions::WINDOW_RANGES["week"]
    assert_equal "2h",  MetricChartDefinitions::WINDOW_RANGES["month"]
    assert_equal "6h",  MetricChartDefinitions::WINDOW_RANGES["quarter"]
  end

  test "metrics_historical_step equals the per-point aggregation range seconds" do
    assert_equal "300s",    metrics_historical_step("day")
    assert_equal "1800s",   metrics_historical_step("week")
    assert_equal "7200s",   metrics_historical_step("month")
    assert_equal "21600s",  metrics_historical_step("quarter")
  end

  test "unknown window tokens default to day" do
    assert_equal "5m", window_range(nil)
    assert_equal "5m", window_range("")
    assert_equal "5m", window_range("bogus")
  end

  test "metrics_charts builds the four host charts keyed by id with chart-value dataset" do
    charts = metrics_charts("day")
    assert_equal %w[cpu memory disk network], charts.keys
    charts.each do |key, spec|
      assert_equal key, spec.dig(:data, :name)
      assert_equal "value", spec.dig(:encoding, :y, :field)
    end
  end

  test "cpu chart is a stacked multi-series of the five cpu modes" do
    defn = MetricChartDefinitions::HOST_CHARTS["cpu"]
    modes = %w[idle user system nice io_wait]
    assert_equal modes, defn[:series].map(&:first)
    assert defn[:stack]
    # one query per mode, aligned with the series order
    assert_equal 5, defn[:queries].size
    defn[:queries].each_with_index do |q, i|
      mode = modes[i]
      assert_includes q, "mode=\"#{mode}\""
      assert_includes q, "%{range}"
      refute_includes q, "instance="
    end
  end

  test "memory, disk, and network charts are stacked and free of instance filters" do
    %w[memory disk network].each do |key|
      defn = MetricChartDefinitions::HOST_CHARTS[key]
      assert defn[:stack]
      assert_equal 2, defn[:series].size, "expected 2 series for #{key}"
      refute defn[:queries].any? { |q| q.include?("instance=") }
    end
  end

  test "y_axis_format flows through to the y axis only when present" do
    cpu = metrics_charts("day")["cpu"]
    assert_equal "d", cpu.dig(:encoding, :y, :axis, :format)

    disk = metrics_charts("day")["disk"]
    assert_nil disk.dig(:encoding, :y, :axis), "no axis key should be added when format is blank"
  end

  test "chart marks are clipped to the plot frame so data never spills past the axes" do
    %w[cpu memory disk network].each do |key|
      spec = metrics_charts("day")[key]
      # every layer's mark must clip to the plot area
      spec[:layer].each do |l|
        mark = l[:mark]
        assert_equal true, mark[:clip], "#{key} layer #{l.inspect} should clip"
      end
    end
  end

  # The tooltip lives in the hover-circle layer (the last layer) of each chart spec.
  def chart_tooltip_encoding(spec)
    spec.dig(:layer, -1, :encoding, :tooltip)
  end

  test "tooltip labels each value with the chart's y-axis unit" do
    { "cpu" => "%", "memory" => "GB", "disk" => "GB", "network" => "Mbit/s" }.each do |key, unit|
      defn = MetricChartDefinitions::HOST_CHARTS[key]
      tooltip = chart_tooltip_encoding(metrics_charts("day")[key])
      value_entry = tooltip.find { |e| e[:field] == "value" }
      assert_equal defn[:y_title], value_entry[:title], "tooltip unit title for #{key}"
      assert_equal unit, value_entry[:title]
    end
  end

  test "tooltip format is integer for cpu and two decimals otherwise" do
    cpu_tooltip  = chart_tooltip_encoding(metrics_charts("day")["cpu"])
    mem_tooltip  = chart_tooltip_encoding(metrics_charts("day")["memory"])
    disk_tooltip = chart_tooltip_encoding(metrics_charts("day")["disk"])
    net_tooltip  = chart_tooltip_encoding(metrics_charts("day")["network"])
    assert_equal ".0f", cpu_tooltip.find { |e| e[:field] == "value" }[:format]
    assert_equal ".2f", mem_tooltip.find { |e| e[:field] == "value" }[:format]
    assert_equal ".2f", disk_tooltip.find { |e| e[:field] == "value" }[:format]
    assert_equal ".2f", net_tooltip.find { |e| e[:field] == "value" }[:format]
  end

  test "queries reference host_* metrics, not node_*" do
    stub_range_rows([])
    end_time = Time.current
    metrics_points(window_token: "day", start_time: end_time - 3600, end_time: end_time, step: "60s")
    assert @captured_queries.any?
    @captured_queries.each do |q|
      assert_match(/host_(cpu|memory|network|filesystem)/, q)
      refute_includes q, "node_"
    end
  end

  test "metrics_charts do not pin an x domain so the axis creeps with live data" do
    charts = metrics_charts("week")
    charts.each_value do |spec|
      scale = spec.dig(:encoding, :x, :scale)
      # auto domain: no explicit extent, so Vega derives it from the streamed points each
      # poll and the newest data marches into the right edge (live creeping)
      refute scale.key?(:domain), "x scale should not pin a domain (got #{scale.inspect})"
      # nice disabled keeps the auto extent flush against the frame instead of puffing out
      # to friendly time boundaries on either side
      assert_equal false, scale[:nice]
    end
  end

  test "metrics_time_domain returns an aligned 24h day window" do
    step_ms = 300 * 1000  # 5m per point for a day
    start_ms, end_ms = metrics_time_domain
    assert_equal 24.hours.to_i * 1000, end_ms - start_ms
    assert_equal 0, end_ms % step_ms
  end

  test "metrics_query_bounds returns a grid-aligned advancing window" do
    ref = Time.current
    start_t, end_t = metrics_query_bounds("day", now: ref)
    # grid aligned: end is a whole 5m step at/before the reference
    assert_equal 0, end_t.to_i % 300
    assert_in_delta 24.hours.to_i, (end_t - start_t).to_i, 1
    assert_operator end_t.to_i, :<=, ref.to_i
  end

  test "pad_missing_points fills absent slots with null values on the step grid" do
    step_s = 300
    base = Time.at(1_700_000_000).to_i # arbitrary wall-clock second that is a multiple of step
    start_ms = base * 1000
    present = [
      { "time" => start_ms, "value" => 1.0 },
      # middle slot deliberately absent -> should become a nil gap
      { "time" => (base + 2 * step_s) * 1000, "value" => 3.0 }
    ]

    padded = send(:pad_missing_points, present,
                  start_time: Time.at(base), end_time: Time.at(base + 2 * step_s),
                  step_seconds: step_s)

    assert_equal 3, padded.size
    times = padded.map { |row| row["time"] }
    assert_equal [ start_ms, (base + step_s) * 1000, (base + 2 * step_s) * 1000 ], times
    assert_equal 1.0, padded[0]["value"]
    assert_nil padded[1]["value"], "missing middle slot should carry a null value (gap)"
    assert_equal 3.0, padded[2]["value"]
  end

  test "pad_missing_points pads each stacked series independently" do
    step_s = 60
    base = Time.at(1_700_000_000).to_i
    start_ms = base * 1000
    end_ms   = (base + step_s) * 1000
    rows = [
      { "time" => start_ms, "value" => 2.0, "series" => "a" },        # series a at slot 0
      { "time" => end_ms,   "value" => 5.0, "series" => "a" },        # series a at slot 1
      { "time" => start_ms, "value" => 9.0, "series" => "b" }        # series b missing slot 1
    ]

    padded = send(:pad_missing_points, rows,
                  start_time: Time.at(base), end_time: Time.at(base + step_s),
                  step_seconds: step_s)

    a = padded.select { |row| row["series"] == "a" }
    b = padded.select { |row| row["series"] == "b" }
    assert_equal 2, a.size
    assert_equal [ 2.0, 5.0 ], a.map { |row| row["value"] }
    assert_equal 2, b.size
    assert_equal [ 9.0, nil ], b.map { |row| row["value"] }, "series b's gap at slot 1 stays null"
  end
end
