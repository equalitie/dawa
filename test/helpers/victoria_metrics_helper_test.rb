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

  test "metrics_charts pins the x scale domain to the full requested window" do
    before = Time.current
    charts = metrics_charts("week")
    after = Time.current
    charts.each_value do |spec|
      domain = spec.dig(:encoding, :x, :scale, :domain)
      assert_equal 2, domain.size
      assert_in_delta before.to_f * 1000, domain.last, after.to_f * 1000
      assert_in_delta (before - 7.days).to_f * 1000, domain.first, (after - 7.days).to_f * 1000
    end
  end

  test "metrics_time_domain defaults to the day window" do
    now = Time.current
    start_ms, end_ms = metrics_time_domain
    assert_in_delta now.to_f * 1000, end_ms, 10_000
    assert_in_delta (now - 24.hours).to_f * 1000, start_ms, 10_000
  end
end
