require "test_helper"

#
# Tests for Metrics::VictoriametricsHelper: chart spec construction, per-window aggregation
# ranges, and the per-chart point rows the metrics controller consumes.
#
# The VictoriaMetrics service is stubbed at its client so these run without a live instance.
#
class VictoriametricsHelperTest < ActiveSupport::TestCase
  # `define_charts`/`metrics_points` call `t(...)` for column labels and `chart_definition` for the
  # definitions, so the helper is exercised through a view context rather than a bare object.
  def helper = @helper ||= ApplicationController.new.view_context

  # Replace the service's client for the duration of the block, recording each range query.
  def with_stubbed_service(record: nil)
    original = VictoriaMetrics.instance_method(:client)
    captured = []
    fake = Object.new
    fake.define_singleton_method(:query_range) do |**kw|
      captured << kw
      { "resultType" => "matrix", "result" => [ { "metric" => {}, "values" => [ [ 100.0, "1.5" ] ] } ] }
    end
    fake.define_singleton_method(:query) { |**_kw| { "resultType" => "vector", "result" => [] } }

    VictoriaMetrics.send(:define_method, :client) { fake }
    result = yield
    record&.replace(captured)
    result
  ensure
    VictoriaMetrics.send(:define_method, :client, original) if original
  end

  ##
  ## chart definitions
  ##

  test "the catalogue defines the host charts and the per-instance charts" do
    assert_equal %w[host_cpu host_memory host_disk host_network app_memory app_cpu app_network app_disk],
                 Metrics::ChartDefinitions::CHARTS.keys
  end

  test "every definition names a context, and the accessors split the catalogue by it" do
    # An untagged definition would be invisible to both accessors and so never rendered.
    Metrics::ChartDefinitions::CHARTS.each do |key, defn|
      assert_includes %i[host app], defn[:context], "#{key} has no usable context"
    end

    assert_equal %w[host_cpu host_memory host_disk host_network], helper.host_chart_names
    assert_equal %w[app_memory app_cpu app_network app_disk], helper.app_chart_names
    assert_equal helper.chart_definition_names.sort,
                 (helper.host_chart_names + helper.app_chart_names).sort
  end

  test "every chart definition has the keys the spec builder reads" do
    Metrics::ChartDefinitions::CHARTS.each do |key, defn|
      assert defn[:title].present?, "#{key} has no title"
      assert_includes %i[single series dynamic], defn[:kind], "#{key} has an unknown kind"

      if defn[:kind] == :series
        assert defn[:series].any?, "#{key} has no series"
        assert_equal defn[:series].size, defn[:queries].size,
                     "#{key}: one query per series, or the stack colours and the data disagree"
      else
        assert defn[:query].present?, "#{key} has no query"
      end
    end
  end

  test "every dynamic chart splits by a label the query keeps, and names no fixed series" do
    # The whole point of :dynamic is that the series set is unknown until the data arrives, so
    # a `series` list here would silently reintroduce fixed colours for a changing set.
    dynamic = Metrics::ChartDefinitions::CHARTS.select { |_key, defn| defn[:kind] == :dynamic }
    refute_empty dynamic

    dynamic.each do |key, defn|
      assert_nil defn[:series], "#{key} must not list fixed series"
      assert defn[:color_field].present?, "#{key} needs a row field to stack by"
      assert defn[:series_label].present?, "#{key} needs a metric label to tag rows with"
      assert_includes defn[:query], "%{filter}", "#{key}: the instance selector has nowhere to go"
    end
  end

  test "queries interpolate %{range} rather than hard-coding a window" do
    Metrics::ChartDefinitions::CHARTS.each_value do |defn|
      Array(defn[:queries] || defn[:query]).each do |q|
        assert_includes q, "%{range}", "a query pinned its own range instead of using the window"
      end
    end
  end

  ##
  ## specs
  ##

  test "define_charts returns a spec per requested key, named for that key" do
    specs = helper.define_charts(keys: %w[host_cpu host_memory], window: "day")

    assert_equal %w[host_cpu host_memory], specs.keys
    specs.each do |key, spec|
      # The JS streams into the dataset named after the key, so these must agree.
      assert_equal key, spec.dig(:data, :name)
    end
  end

  test "define_charts only builds the keys it was asked for" do
    specs = helper.define_charts(keys: [ "host_disk" ], window: "day")

    assert_equal [ "host_disk" ], specs.keys
  end

  test "each spec's dataset name matches its chart key" do
    # metrics_controller.js streams into a dataset named after the key (datasetName(key)), and
    # streams by key into a separate dataset per chart. If the spec names its data anything
    # else, view.change targets a dataset that does not exist and the chart silently freezes.
    helper.define_charts(keys: helper.host_chart_names, window: "day").each do |key, spec|
      assert_equal key, spec.dig(:data, :name), "#{key} must stream into a dataset named for its key"
    end
  end

  test "a stacked chart's spec is built from its series" do
    spec = helper.define_charts(keys: [ "host_cpu" ], window: "day").fetch("host_cpu")

    assert_equal "charts.cpu", spec.dig(:title)
    assert spec[:layer].is_a?(Array), "a series chart is layered"
  end

  test "an unknown chart key yields no spec rather than raising" do
    # A typo in the dashboard list should not take the whole page down.
    assert_empty helper.define_charts(keys: [ "no_such_chart" ], window: "day")
  end

  ##
  ## windows
  ##

  test "each window maps to a point-tiling aggregation range" do
    assert_equal "5m",  helper.window_range("day")
    assert_equal "30m", helper.window_range("week")
    assert_equal "2h",  helper.window_range("month")
    assert_equal "6h",  helper.window_range("quarter")
  end

  test "metrics_historical_step is the window range in seconds" do
    assert_equal "300s",   helper.metrics_historical_step("day")
    assert_equal "1800s",  helper.metrics_historical_step("week")
    assert_equal "7200s",  helper.metrics_historical_step("month")
    assert_equal "21600s", helper.metrics_historical_step("quarter")
  end

  test "an unknown window token falls back to day" do
    assert_equal "5m", helper.window_range(nil)
    assert_equal "5m", helper.window_range("")
    assert_equal "5m", helper.window_range("bogus")
  end

  test "the query window is grid-aligned and ends in the past" do
    ref = Time.current
    start_t, end_t = helper.metrics_query_bounds("day", now: ref)

    assert_equal 0, end_t.to_i % 300, "end must sit on a whole 5m step"
    assert_operator end_t.to_i, :<=, ref.to_i
    assert_in_delta 24.hours.to_i, (end_t - start_t).to_i, 1
  end

  ##
  ## points
  ##

  test "metrics_points queries only the requested keys" do
    recorded = []
    with_stubbed_service(record: recorded) do
      helper.metrics_points(keys: [ "host_memory" ], window_token: "day",
                            start_time: 1.hour.ago, end_time: Time.current)
    end

    assert recorded.any?
    recorded.each { |call| assert_match(/host_memory/, call[:query]) }
  end

  test "metrics_points returns a row set per requested key" do
    with_stubbed_service do
      points = helper.metrics_points(keys: %w[host_cpu host_memory], window_token: "day",
                                     start_time: 1.hour.ago, end_time: Time.current)

      assert_equal %w[host_cpu host_memory], points.keys
      points.each_value { |rows| assert rows.any? }
    end
  end

  test "an unknown key yields an empty row set rather than raising" do
    with_stubbed_service do
      points = helper.metrics_points(keys: [ "no_such_chart" ], window_token: "day",
                                     start_time: 1.hour.ago, end_time: Time.current)

      assert_equal({ "no_such_chart" => [] }, points)
    end
  end

  test "metrics_points passes the window's step to the query" do
    recorded = []
    with_stubbed_service(record: recorded) do
      helper.metrics_points(keys: [ "host_memory" ], window_token: "week",
                            start_time: 1.hour.ago, end_time: Time.current)
    end

    assert_equal "1800s", recorded.first[:step]
  end

  test "a filter becomes a quoted PromQL label selector in the query" do
    # The selector goes straight into the query text, so an unquoted value is a PromQL parse
    # error. This pins the exact text rather than just that the filter was applied.
    recorded = []
    with_stubbed_service(record: recorded) do
      helper.metrics_points(keys: [ "app_memory" ], window_token: "day",
                            start_time: 1.hour.ago, end_time: Time.current,
                            filter: { dc_app: "metrics" })
    end

    query = recorded.first[:query]
    assert_includes query, %(docker_memory_usage{dc_app="metrics"}[5m])
    refute_includes query, "%{filter}"
  end

  test "without a filter the selector is empty, so the template still parses" do
    recorded = []
    with_stubbed_service(record: recorded) do
      helper.metrics_points(keys: [ "app_memory" ], window_token: "day",
                            start_time: 1.hour.ago, end_time: Time.current)
    end

    assert_includes recorded.first[:query], "docker_memory_usage[5m]"
  end

  test "a dynamic chart is stacked and colours by its label, with no fixed domain" do
    spec = helper.define_charts(keys: [ "app_memory" ], window: "day",
                                filter: { dc_app: "metrics" }).fetch("app_memory")

    # Rows are tagged into "series" by series_label, so colouring by the metric label name
    # itself (containerName) finds nothing and every band collapses into one.
    assert_equal "series", spec.dig(:encoding, :color, :field)
    # A nil legend title renders as the literal word "undefined".
    assert_equal "Container", spec.dig(:encoding, :color, :title)
    # Naming a domain would drop any container the domain does not list; the set is dynamic.
    assert_nil spec.dig(:encoding, :color, :scale, :domain)
    assert spec.dig(:encoding, :color, :scale, :range).any?
    assert_equal "zero", spec.dig(:encoding, :y, :stack)
    assert_equal "area", spec.dig(:layer, 0, :mark, :type)
  end

  test "a dynamic chart's rows are tagged by container name" do
    # One query, several containers: each result becomes its own band, so the rows have to
    # carry the value of the definition's series_label rather than being tagged by instance.
    payload = {
      "resultType" => "matrix",
      "result" => [
        { "metric" => { "instance" => "host:9100", "containerName" => "caddy" },
          "values" => [ [ 100.0, "2048" ] ] },
        { "metric" => { "instance" => "host:9100", "containerName" => "dawa" },
          "values" => [ [ 100.0, "4096" ] ] }
      ]
    }
    fake = Object.new
    fake.define_singleton_method(:query_range) { |**_kw| payload }

    with_client(fake) do
      rows = helper.metrics_points(keys: [ "app_memory" ], window_token: "day",
                                   start_time: Time.at(60 * 300), end_time: Time.at(60 * 300),
                                   step: "5m")["app_memory"]

      assert_equal %w[caddy dawa], rows.map { |row| row["series"] }.uniq.sort
    end
  end

  test "metrics_points logs a query that returns no samples" do
    # An empty result pads into an all-null grid and the chart draws a flat zero axis, which
    # looks the same as a working chart with no activity. The log line is the only pointer to
    # which query came back empty.
    empty = Object.new
    empty.define_singleton_method(:query_range) { |**_kw| { "resultType" => "matrix", "result" => [] } }

    with_client(empty) do
      with_log_io do |io|
        helper.metrics_points(keys: [ "host_memory" ], window_token: "day",
                              start_time: 1.hour.ago, end_time: Time.current)

        assert_match(/WARN -- : metrics query returned no samples host_memory/, io.string)
        assert_match(/avg_over_time\(host_memory/, io.string)
      end
    end
  end

  test "pad_missing_points fills absent slots with nulls on the step grid" do
    step_s = 300
    base = Time.at(1_700_000_000).to_i
    start_ms = base * 1000
    present = [
      { "time" => start_ms, "value" => 1.0 },
      # the middle slot is deliberately absent -> a nil gap
      { "time" => (base + 2 * step_s) * 1000, "value" => 3.0 }
    ]

    padded = helper.send(:pad_missing_points, present,
                         start_time: Time.at(base), end_time: Time.at(base + 2 * step_s),
                         step_seconds: step_s)

    assert_equal 3, padded.size
    assert_equal [ start_ms, (base + step_s) * 1000, (base + 2 * step_s) * 1000 ],
                 padded.map { |row| row["time"] }
    assert_nil padded[1]["value"], "a missing slot must carry a null value, not be dropped"
  end

  test "pad_missing_points pads each stacked series independently" do
    step_s = 60
    base = Time.at(1_700_000_000).to_i
    start_ms = base * 1000
    end_ms   = (base + step_s) * 1000
    rows = [
      { "time" => start_ms, "value" => 2.0, "series" => "a" },
      { "time" => end_ms,   "value" => 5.0, "series" => "a" },
      { "time" => start_ms, "value" => 9.0, "series" => "b" } # b is missing slot 1
    ]

    padded = helper.send(:pad_missing_points, rows,
                         start_time: Time.at(base), end_time: Time.at(base + step_s),
                         step_seconds: step_s)

    a = padded.select { |row| row["series"] == "a" }
    b = padded.select { |row| row["series"] == "b" }
    assert_equal [ 2.0, 5.0 ], a.map { |row| row["value"] }
    assert_equal [ 9.0, nil ], b.map { |row| row["value"] }, "series b's gap stays null"
  end

  private

  # Replace the service's client for the block, restoring it afterwards. Prefer this over
  # with_stubbed_service when the stub has to return something other than a data payload.
  def with_client(fake)
    original = VictoriaMetrics.instance_method(:client)
    VictoriaMetrics.send(:define_method, :client) { fake }
    yield
  ensure
    VictoriaMetrics.send(:define_method, :client, original) if original
  end

  def with_log_io
    io = StringIO.new
    prior = Rails.logger
    Rails.logger = Logger.new(io)
    yield io
  ensure
    Rails.logger = prior
  end
end
