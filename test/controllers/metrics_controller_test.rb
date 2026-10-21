require_relative "../test_helper"

#
# Integration tests for the host metrics dashboard.
#
# VictoriaMetrics is stubbed at the service's client, so these run without a live backend. What
# matters here is the contract between the two actions: `show` renders a Vega spec per dashboard
# chart, and `data` returns point rows for THE SAME set of charts, in the grid-aligned window the
# specs expect.
#
class MetricsControllerTest < ActionDispatch::IntegrationTest
  # The charts the host dashboard renders, taken from the definitions themselves rather than a
  # second hardcoded list that could drift away from them.
  HOST_CHARTS = Metrics::ChartDefinitions::CHARTS.select { |_k, defn| defn[:context] == :host }.keys.freeze

  def setup
    @user = User.create!(username: "metrics-test-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  # Stub the service's memoized gem client so the query path is deterministic, restoring it
  # afterwards so other tests keep working. Records each range query's start/end/step.
  def with_stubbed_service(record: nil)
    original = VictoriaMetrics.instance_method(:client)
    captured = []

    fake = Object.new
    fake.define_singleton_method(:query_range) do |**kw|
      captured << kw.slice(:query, :start, :end, :step)
      { "resultType" => "matrix",
        "result" => [ { "metric" => {}, "values" => [ [ 100.0, "50.5" ], [ 160.0, "52.0" ] ] } ] }
    end
    fake.define_singleton_method(:query) { |**_kw| { "resultType" => "vector", "result" => [] } }

    VictoriaMetrics.send(:define_method, :client) { fake }
    result = yield
    record&.replace(captured)
    result
  ensure
    VictoriaMetrics.send(:define_method, :client, original) if original
  end

  test "show renders one chart widget per dashboard chart" do
    login_as(@user)
    get metrics_path

    assert_response :success
    expected = HOST_CHARTS.size
    assert_select ".chart", count: expected
    assert_select '[data-metrics-target="chart"]', count: expected
  end

  test "show gives each chart its own dataset, named for the chart key" do
    # The JS streams into a named dataset per chart, so the spec's data name has to match the key
    # the endpoint returns; otherwise `view.change(key, ...)` finds nothing to update.
    login_as(@user)
    get metrics_path

    HOST_CHARTS.each do |key|
      assert_select "[data-chart-key=?]", key
    end
  end

  test "show requires admin" do
    get metrics_path

    assert_response :redirect
    assert_redirected_to login_path
  end

  test "data queries only the charts the client asked for" do
    # The page sends the keys it rendered (`data-chart-key`), so the endpoint does not have to
    # guess and does not query charts nobody is looking at.
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(charts: [ "host_memory" ]), headers: { "Accept" => "application/json" }

      assert_response :success
      assert_equal [ "host_memory" ], JSON.parse(response.body).fetch("points").keys
    end

    assert recorded.any?
    recorded.each { |call| assert_match(/host_memory/, call[:query], "only the requested chart is queried") }
  end

  test "data accepts the array parameter the browser sends" do
    # `charts[]=a&charts[]=b`, which Rails parses into an array.
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path(charts: [ "host_cpu", "host_disk" ]),
          headers: { "Accept" => "application/json" }

      assert_response :success
      assert_equal %w[host_cpu host_disk], JSON.parse(response.body).fetch("points").keys
    end
  end

  test "data drops chart keys this dashboard does not know" do
    # The parameter comes from the browser, so unknown keys must not reach the query builder.
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(charts: [ "host_cpu", "no_such_chart", "../../etc/passwd" ]),
          headers: { "Accept" => "application/json" }

      assert_response :success
      assert_equal [ "host_cpu" ], JSON.parse(response.body).fetch("points").keys
    end

    recorded.each { |call| assert_match(/host_cpu/, call[:query]) }
  end

  test "data returns no rows when no keys are given" do
    # `charts[]` is the client saying which charts it rendered. Without it there is nothing to
    # answer for, and inventing a set would query charts the page never drew (and, for the
    # per-instance charts, without the filter they need).
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path, headers: { "Accept" => "application/json" }

      assert_equal [], JSON.parse(response.body).fetch("points").keys
    end
  end

  test "data returns no rows when every requested key is unknown" do
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path(charts: [ "nope" ]), headers: { "Accept" => "application/json" }

      assert_equal [], JSON.parse(response.body).fetch("points").keys
    end
  end

  test "data returns rows for exactly the requested dashboard charts" do
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path(charts: HOST_CHARTS),
          headers: { "Accept" => "application/json" }

      assert_response :success
      body = JSON.parse(response.body)

      assert_equal HOST_CHARTS.sort, body.fetch("points").keys.sort
    end
  end

  test "a filtered request serves only the per-instance charts, filtered by dc_inst" do
    # The app metrics page renders outside /metrics and polls this endpoint with dc_inst.
    # Getting the allowed set or the label wrong here blanks the chart silently: the poll
    # succeeds and returns an empty row set.
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(dc_inst: "ersatz-indri", charts: %w[app_cpu app_memory]),
          headers: { "Accept" => "application/json" }
    end

    assert_equal %w[app_cpu app_memory], JSON.parse(response.body).fetch("points").keys.sort
    recorded.each do |call|
      assert_includes call[:query], %(dc_inst="ersatz-indri"), "the selector must use the instance id"
      refute_includes call[:query], "dc_app", "dc_app is the app definition, not the instance"
    end
  end

  test "a filtered request only serves the charts it asked for" do
    # requested_chart_keys intersects with the catalogue rather than the filtered subset, so the
    # filter is not what restricts the keys: the client's charts[] is. A page that asked for a
    # host chart still gets it, which is why the app page must ask only for its own charts.
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path(dc_inst: "ersatz-indri", charts: [ "host_cpu" ]),
          headers: { "Accept" => "application/json" }

      assert_equal [ "host_cpu" ], JSON.parse(response.body).fetch("points").keys
    end
  end

  test "data pads every chart to a full grid of rows" do
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path(charts: HOST_CHARTS), headers: { "Accept" => "application/json" }

      body = JSON.parse(response.body)
      body.fetch("points").each do |key, rows|
        assert rows.any?, "#{key} returned no rows"
        rows.each do |row|
          assert row.key?("time"), "#{key} row missing time"
          assert row.key?("value"), "#{key} row missing value (nil for gaps)"
        end
      end
    end
  end

  test "a stacked chart's rows are padded per series" do
    # The CPU chart is the dashboard's multi-series one: each mode is padded independently, so a
    # gap in one mode's samples does not shift the others along the axis.
    cpu = Metrics::ChartDefinitions::CHARTS.fetch("host_cpu")

    with_stubbed_service do
      login_as(@user)
      get data_metrics_path(charts: HOST_CHARTS), headers: { "Accept" => "application/json" }

      rows = JSON.parse(response.body).dig("points", "host_cpu")
      assert_equal cpu[:series].size, rows.group_by { |row| row["series"] }.size
    end
  end

  test "a request without keys queries every dashboard chart" do
    # The expensive calls are the per-chart range queries. With no `charts` parameter the endpoint
    # cannot know what is on screen, so it queries the whole dashboard -- every chart's query runs.
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(charts: HOST_CHARTS), headers: { "Accept" => "application/json" }
      assert_response :success
    end

    assert recorded.any?
    # One query family per chart definition, so all four appear in the captured queries.
    assert recorded.any? { |call| call[:query].include?("host_cpu_seconds_total") }, "cpu"
    assert recorded.any? { |call| call[:query].include?("host_memory") }, "memory"
    assert recorded.any? { |call| call[:query].include?("host_filesystem") }, "disk"
    assert recorded.any? { |call| call[:query].include?("host_network") }, "network"
  end

  test "data defaults to the 24 hour day window at a 5 minute step" do
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(charts: HOST_CHARTS), headers: { "Accept" => "application/json" }
      assert_response :success
    end

    assert recorded.any?
    window = recorded.first[:end] - recorded.first[:start]
    assert_in_delta 86_400, window, 60
    assert_equal "300s", recorded.first[:step]
  end

  test "data uses the week window" do
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(window: "week", charts: HOST_CHARTS), headers: { "Accept" => "application/json" }
      assert_response :success
    end

    assert recorded.any?
    window = recorded.first[:end] - recorded.first[:start]
    assert_in_delta 604_800, window, 60
    assert_equal "1800s", recorded.first[:step]
  end

  test "data clamps the quarter window by retention" do
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(window: "quarter", charts: HOST_CHARTS), headers: { "Accept" => "application/json" }
      assert_response :success
    end

    assert recorded.any?
    window = recorded.first[:end] - recorded.first[:start]
    # quarter resolves to 90 days (the 90-day retention cap) with a 6h range step
    assert_in_delta 7_776_000, window, 60
    assert_equal "21600s", recorded.first[:step]
  end

  test "data uses the most recent advancing window" do
    # The endpoint queries the newest completed grid window, so fresh points creep in on each poll.
    before = Time.current
    recorded = []
    with_stubbed_service(record: recorded) do
      login_as(@user)
      get data_metrics_path(window: "day", charts: HOST_CHARTS), headers: { "Accept" => "application/json" }
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
