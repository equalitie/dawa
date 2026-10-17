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
    expected = MetricsController::HOST_CHARTS.size
    assert_select ".chart", count: expected
    assert_select '[data-metrics-target="chart"]', count: expected
  end

  test "show gives each chart its own dataset, named for the chart key" do
    # The JS streams into a named dataset per chart, so the spec's data name has to match the key
    # the endpoint returns; otherwise `view.change(key, ...)` finds nothing to update.
    login_as(@user)
    get metrics_path

    MetricsController::HOST_CHARTS.each do |key|
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

  test "data falls back to every dashboard chart when no keys are given" do
    # A direct request, or a client that predates the parameter: the previous behaviour.
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path, headers: { "Accept" => "application/json" }

      assert_equal MetricsController::HOST_CHARTS.sort,
                   JSON.parse(response.body).fetch("points").keys.sort
    end
  end

  test "data falls back to the dashboard list when every requested key is unknown" do
    # An empty allowlist is not a reason to return nothing: the caller gets the full dashboard
    # rather than a permanently blank page.
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path(charts: [ "nope" ]), headers: { "Accept" => "application/json" }

      assert_equal MetricsController::HOST_CHARTS.sort,
                   JSON.parse(response.body).fetch("points").keys.sort
    end
  end

  test "data returns rows for exactly the dashboard's charts" do
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path, headers: { "Accept" => "application/json" }

      assert_response :success
      body = JSON.parse(response.body)

      # Not every definition in the catalogue: only the charts `show` actually rendered.
      assert_equal MetricsController::HOST_CHARTS.sort, body.fetch("points").keys.sort
    end
  end

  test "data pads every chart to a full grid of rows" do
    with_stubbed_service do
      login_as(@user)
      get data_metrics_path, headers: { "Accept" => "application/json" }

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
      get data_metrics_path, headers: { "Accept" => "application/json" }

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
      get data_metrics_path, headers: { "Accept" => "application/json" }
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
      get data_metrics_path, headers: { "Accept" => "application/json" }
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
      get data_metrics_path(window: "week"), headers: { "Accept" => "application/json" }
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
      get data_metrics_path(window: "quarter"), headers: { "Accept" => "application/json" }
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
