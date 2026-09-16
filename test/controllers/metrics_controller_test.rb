require_relative "../test_helper"

class MetricsControllerTest < ActionDispatch::IntegrationTest
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

  def test_data_responds_success_with_expected_chart_keys
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path, headers: { "Accept" => "application/json" }

      assert_response :success
      body = JSON.parse(response.body)

      expected_keys = %w[cpu memory disk network]
      assert_equal expected_keys, body.fetch("points").keys

      # The stub returns two rows per query. cpu has five mode-series => 5x, others two => 2x.
      assert_equal 10, body["points"]["cpu"].size
      assert_equal 4,  body["points"]["disk"].size
      assert_equal 4,  body["points"]["network"].size
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
end
