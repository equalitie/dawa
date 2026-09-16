require_relative "../test_helper"

class MetricsControllerTest < ActionDispatch::IntegrationTest
  include VictoriaMetricsHelper

  def setup
    @user = User.create!(username: "metrics-test-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  # Stub the service's memoized gem client so the query path is deterministic,
  # restoring the original method afterward (define_method/instance_method-lifting
  # so other tests keep working). Records the start/end/step of each range query.
  def with_stubbed_service(record: nil)
    original = VictoriaMetrics.instance_method(:client)
    captured = []
    fake = Object.new
    fake.define_singleton_method(:query_range) do |**kw|
      captured << kw.slice(:start, :end, :step)
      { "resultType" => "matrix",
        "result" => [ { "metric" => {}, "values" => [ [ 100.0, "50.5" ], [ 160.0, "52.0" ] ] } ] }
    end
    fake.define_singleton_method(:query) { |**_kw| { "resultType" => "vector", "result" => [] } }

    VictoriaMetrics.send(:define_method, :client) { fake }
    result = yield
    record&.replace(captured)
    result
  ensure
    VictoriaMetrics.send(:define_method, :client, original)
  end

  def test_show_renders_all_chart_widgets
    login_as(@user)
    get metrics_path

    assert_response :success
    assert_select ".chart", count: 4
    assert_select '[data-metrics-target="chart"]', count: 4
  end

  def test_show_requires_admin
    get metrics_path
    assert_response :redirect
    assert_redirected_to login_path
  end

  def test_data_responds_success_with_padded_full_grid_rows
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path, headers: { "Accept" => "application/json" }

      assert_response :success
      body = JSON.parse(response.body)

      expected_keys = %w[cpu memory disk network]
      assert_equal expected_keys, body.fetch("points").keys

      # Each stacked chart is padded to a full grid for its number of series (cpu = the 5
      # cpu modes; the others have 2 series), with null value rows standing in where a sample
      # is missing so Vega draws a gap instead of bridging it.
      expected_series = { "cpu" => 5, "memory" => 2, "disk" => 2, "network" => 2 }
      expected_series.each do |key, series_count|
        rows = body["points"][key]
        assert_equal series_count, rows.group_by { |row| row["series"] }.size, "series count for #{key}"
        rows.each do |row|
          assert row.key?("time"), "#{key} row missing time"
          assert row.key?("value"), "#{key} row missing value (nil for gaps)"
        end
      end
    end
  end

  def test_data_defaults_to_24_hour_day_window
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path, headers: { "Accept" => "application/json" }
      assert_response :success
    end

    assert recorded.any?
    window = recorded.first[:end] - recorded.first[:start]
    assert_in_delta 86_400, window, 60
    assert_equal "300s", recorded.first[:step]
  end

  def test_data_uses_week_window
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(window: "week"), headers: { "Accept" => "application/json" }
      assert_response :success
    end

    assert recorded.any?
    window = recorded.first[:end] - recorded.first[:start]
    assert_in_delta 604_800, window, 60
    assert_equal "1800s", recorded.first[:step]
  end

  def test_data_clamps_month_and_quarter_by_retention
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(window: "quarter"), headers: { "Accept" => "application/json" }
      assert_response :success
    end

    assert recorded.any?
    window = recorded.first[:end] - recorded.first[:start]
    # quarter resolves to 90 days (the 90-day retention cap) with a 6h range step
    assert_in_delta 7_776_000, window, 60
    assert_equal "21600s", recorded.first[:step]
  end

  def test_data_uses_the_most_recent_advancing_window
    # The data endpoint should query the newest completed grid window (starting from now-ish),
    # so fresh points creep in on each poll and feed the auto-derived live axis.
    before = Time.current
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(window: "day"), headers: { "Accept" => "application/json" }
      assert_response :success
    end

    assert recorded.any?
    start_t, end_t = recorded.first[:start], recorded.first[:end]
    # end is the newest completed 5m step at/before the request
    assert_operator end_t, :<=, before.to_i
    assert_equal 0, end_t % 300
    assert_in_delta 24.hours.to_i, end_t - start_t, 1
  end
end
