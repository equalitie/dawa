require "test_helper"

#
# Tests for the VictoriaMetricsHelper: chart spec construction and the
# per-chart point rows the metrics controller consumes. The VM service client
# is stubbed so these run without a live VictoriaMetrics instance.
#
class VictoriaMetricsHelperTest < ActiveSupport::TestCase
  include VictoriaMetricsHelper

  setup do
    @instance = metrics_host_instance
  end

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

  test "metrics_host_instance reads the configured value" do
    assert_equal "host.docker.internal:9100", metrics_host_instance
  end

  test "metrics_historical_interval_ms reflects the 1 minute config" do
    assert_equal 60_000, metrics_historical_interval_ms
  end

  test "metrics_historical_step derives from the window to cap point count" do
    assert_equal "432s",   metrics_historical_step(24.hours)
    assert_equal "3024s",  metrics_historical_step(7.days)
    assert_equal "12960s", metrics_historical_step(30.days)
    assert_equal "38880s", metrics_historical_step(90.days)
  end

  test "metrics_historical_step never drops below one second" do
    assert_equal "1s", metrics_historical_step(1.second)
    assert_equal "1s", metrics_historical_step(30.seconds)
  end

  test "words_to_time parses various duration units into seconds" do
    {
      "1 second" => 1, "45 seconds" => 45,
      "1 minute" => 60, "2 minutes" => 120,
      "1 hour" => 3600, "2 hours" => 7200,
      "1 day" => 86_400, "1 week" => 604_800
    }.each do |words, expected_seconds|
      assert_equal expected_seconds, send(:words_to_time, words).to_i, "for #{words.inspect}"
    end
  end

  test "words_to_time raises ArgumentError for unsupported text" do
    assert_raises(ArgumentError) { send(:words_to_time, "10 anything") }
    assert_raises(ArgumentError) { send(:words_to_time, "a minute") }
  end

  test "metrics_window defaults to 24 hours when no param is given" do
    assert_equal 86_400, metrics_window.to_i
    assert_equal 86_400, metrics_window(nil).to_i
    assert_equal 86_400, metrics_window("").to_i
  end

  test "metrics_window accepts a duration param" do
    assert_equal 604_800, metrics_window("7 days").to_i
    assert_equal 2_592_000, metrics_window("30 days").to_i
  end

  test "metrics_window clamps to the historical maximum window" do
    # max is 90 days (7,776,000s)
    assert_equal 7_776_000, metrics_window("90 days").to_i
    assert_equal 7_776_000, metrics_window("200 days").to_i
  end

  test "metrics_charts builds the host charts with chart-key datasets" do
    charts = metrics_charts
    assert_equal %w[cpu memory disk network], charts.keys
    charts.each do |key, spec|
      assert_equal key, spec.dig(:data, :name), "expected dataset named after chart key for #{key}"
      assert_equal "value", spec.dig(:encoding, :y, :field)
    end
    assert_equal "container", charts["cpu"][:width]
  end

  test "disk chart combines capacity, used, and free as colored overlays" do
    spec = metrics_charts["disk"]
    assert_equal "Disk Usage", spec[:title]
    assert_equal "GB", spec.dig(:encoding, :y, :title)
    assert_equal "series", spec.dig(:encoding, :color, :field)
    assert_equal [ "free", "used" ], spec.dig(:encoding, :color, :scale, :domain)
    # disk is independent measures and must overlay, not stack
    assert_equal "zero", spec.dig(:encoding, :y, :stack)
  end

  test "network chart colors by series domain ingress/egress" do
    spec = metrics_charts["network"]
    assert_equal [ "ingress", "egress" ], spec.dig(:encoding, :color, :scale, :domain)
    assert_equal "series", spec.dig(:encoding, :color, :field)
  end

  test "disk series render as lines while network series render as areas" do
    disk = metrics_charts["disk"]
    network = metrics_charts["network"]
    assert_equal "area", disk.dig(:layer, 0, :mark, :type)
    assert_equal "area", network.dig(:layer, 0, :mark, :type)
  end

  test "metrics_charts pins the x scale domain to the full requested window" do
    before = Time.current
    charts = metrics_charts("7 days")
    after = Time.current
    charts.each_value do |spec|
      domain = spec.dig(:encoding, :x, :scale, :domain)
      assert_equal 2, domain.size
      # domain spans the full 7-day window ending around now
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

  test "queries are scoped to the configured host instance" do
    stub_range_rows([])
    end_time = Time.current
    metrics_points(start_time: end_time - 3600, end_time: end_time, step: "60s")
    assert @captured_queries.any?, "expected at least one query captured"
    @captured_queries.each do |q|
      assert_includes q, 'instance="host.docker.internal:9100"'
    end
  end

  test "metrics_points returns per-chart rows from the service" do
    stub_range_rows([ [ 100.0, "50.5" ], [ 160.0, "52.0" ] ])
    end_time = Time.current
    points = metrics_points(start_time: end_time - 3600, end_time: end_time, step: "60s")

    assert_equal %w[cpu memory disk network], points.keys
    assert_equal 2, points["cpu"].size
    assert_equal 100_000, points["cpu"].first["time"]
    assert_equal 50.5, points["cpu"].first["value"]
    # disk combines three queries (capacity/used/free) => 3x single-series rows
    assert_equal 4, points["disk"].size
    assert_equal %w[free used], points["disk"].map { |r| r["series"] }.uniq.sort
    # network combines two queries => 2x single-series rows
    assert_equal 4, points["network"].size
    assert_includes %w[ingress egress], points["network"].first["series"]
    assert_equal 2, points["network"].group_by { |r| r["series"] }.size
  end
end
