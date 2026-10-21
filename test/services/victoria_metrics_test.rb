require "test_helper"
require "stringio"
require "logger"

#
# Unit tests for the VictoriaMetrics service. The gem client is stubbed so these
# run without a live VictoriaMetrics instance; they pin the normalization between
# the raw matrix/vector payload and the point rows the Vega chart layer consumes.
#
class VictoriaMetricsTest < ActiveSupport::TestCase
  setup do
    @service = VictoriaMetrics.new
  end

  def fake_client(query_range: nil, query: nil)
    stub = Object.new
    stub.define_singleton_method(:query_range) { |**_kwargs| query_range }
    stub.define_singleton_method(:query) { |**_kwargs| query }
    stub
  end

  test "host_instance reads the configured value" do
    assert_equal "host.docker.internal:9100", @service.host_instance
  end

  test "normalizes a single-series matrix into ms-epoch point rows" do
    payload = {
      "resultType" => "matrix",
      "result" => [
        { "metric" => { "instance" => "host.docker.internal:9100", "job" => "node" },
          "values" => [ [ 1_787_518_020.0, "7960.28" ], [ 1_787_518_080.0, "7800.0" ] ] }
      ]
    }
    with_client(fake_client(query_range: payload)) do
      rows = @service.range("up", start_time: 1_787_517_900, end_time: 1_787_518_100, step: "60s")
      assert_equal(
        [
          { "time" => 1_787_518_020_000, "value" => 7960.28, "series" => "host.docker.internal:9100" },
          { "time" => 1_787_518_080_000, "value" => 7800.0, "series" => "host.docker.internal:9100" }
        ],
        rows
      )
    end
  end

  test "tags a single series too, so one result still carries its label" do
    # Tagging only when several series came back left a lone result unlabelled, so a chart
    # colouring or padding by this field drew one anonymous band instead of one per series.
    payload = {
      "resultType" => "matrix",
      "result" => [ { "metric" => { "instance" => "only-one" }, "values" => [ [ 100.0, "1.0" ] ] } ]
    }
    with_client(fake_client(query_range: payload)) do
      rows = @service.range("up", start_time: 0, end_time: 300, step: "60s")
      assert_equal "only-one", rows.first["series"]
    end
  end

  test "series_label picks which metric label tags the rows" do
    # A per-container chart splits one query into series by dc_name, not by instance.
    payload = {
      "resultType" => "matrix",
      "result" => [
        { "metric" => { "instance" => "host:9100", "dc_name" => "caddy" },
          "values" => [ [ 100.0, "2.0" ] ] },
        { "metric" => { "instance" => "host:9100", "dc_name" => "dawa" },
          "values" => [ [ 100.0, "3.0" ] ] }
      ]
    }
    with_client(fake_client(query_range: payload)) do
      rows = @service.range("mem", start_time: 0, end_time: 300, step: "60s", series_label: "dc_name")
      assert_equal %w[caddy dawa], rows.map { |row| row["series"] }
    end
  end

  test "sorts multi-series rows by time and tags them with the instance label" do
    payload = {
      "resultType" => "matrix",
      "result" => [
        { "metric" => { "instance" => "host-a" }, "values" => [ [ 200.0, "1.0" ] ] },
        { "metric" => { "instance" => "host-b" }, "values" => [ [ 100.0, "2.0" ] ] }
      ]
    }
    with_client(fake_client(query_range: payload)) do
      rows = @service.range("up", start_time: 0, end_time: 300, step: "60s")
      assert_equal 100_000, rows[0]["time"]
      assert_equal "host-b", rows[0]["series"]
      assert_equal 200_000, rows[1]["time"]
      assert_equal "host-a", rows[1]["series"]
    end
  end

  test "returns empty array when the matrix has no result" do
    payload = { "resultType" => "matrix", "result" => [] }
    with_client(fake_client(query_range: payload)) do
      assert_equal [], @service.range("up", start_time: 0, end_time: 1, step: "60s")
    end
  end

  test "returns empty array when VictoriaMetrics is unreachable, and logs the failure" do
    raising = Object.new
    raising.define_singleton_method(:query_range) do |**_kwargs|
      raise Prometheus::ApiClient::Client::RequestError, "connection refused"
    end
    with_client(raising) do
      with_log_io do |io|
        assert_equal [], @service.range("up", start_time: 0, end_time: 1, step: "60s")

        assert_match(/ERROR -- : VictoriaMetrics query_range failed url=\S+ up connection refused/, io.string)
        assert_equal 1, io.string.scan("connection refused").size
      end
    end
  end

  test "current returns the instant value as a Float" do
    payload = {
      "resultType" => "vector",
      "result" => [ { "metric" => { "instance" => "host.docker.internal:9100" }, "value" => [ 1_787_518_080.0, "7847.8" ] } ]
    }
    with_client(fake_client(query: payload)) do
      assert_equal 7847.8, @service.current("up")
    end
  end

  test "current returns nil when the vector is empty" do
    with_client(fake_client(query: { "resultType" => "vector", "result" => [] })) do
      assert_nil @service.current("up")
    end
  end

  test "current returns nil when VictoriaMetrics is unreachable, and logs the failure" do
    raising = Object.new
    raising.define_singleton_method(:query) do |**_kwargs|
      raise Prometheus::ApiClient::Client::RequestError, "connection refused"
    end
    with_client(raising) do
      with_log_io do |io|
        assert_nil @service.current("up")

        assert_match(/ERROR -- : VictoriaMetrics query failed url=\S+ up connection refused/, io.string)
        assert_equal 1, io.string.scan("connection refused").size
      end
    end
  end

  test "vector returns the raw series list from an instant query" do
    payload = {
      "resultType" => "vector",
      "result" => [
        { "metric" => { "instance" => "host-a", "job" => "node" }, "value" => [ 1_787_518_080.0, "1" ] },
        { "metric" => { "instance" => "host-b", "job" => "node" }, "value" => [ 1_787_518_080.0, "0" ] }
      ]
    }
    with_client(fake_client(query: payload)) do
      series = @service.vector("up")
      assert_equal 2, series.size
      assert_equal "host-a", series[0]["metric"]["instance"]
      assert_equal [ 1_787_518_080.0, "1" ], series[0]["value"]
    end
  end

  test "vector returns empty when the instant query has no result" do
    with_client(fake_client(query: { "resultType" => "vector", "result" => [] })) do
      assert_equal [], @service.vector("up")
    end
  end

  test "vector raises when VictoriaMetrics is unreachable" do
    raising = Object.new
    raising.define_singleton_method(:query) do |**_kwargs|
      raise Prometheus::ApiClient::Client::RequestError, "connection refused"
    end
    with_client(raising) do
      assert_raises(Prometheus::ApiClient::Client::RequestError) do
        @service.vector("up")
      end
    end
  end

  test "default value key is 'value' and can be overridden" do
    assert_equal "value", VictoriaMetrics.new.value_key
    custom = VictoriaMetrics.new(value_key: "mem_mb")
    payload = { "resultType" => "matrix", "result" => [ { "metric" => {}, "values" => [ [ 100.0, "12.5" ] ] } ] }
    with_client(fake_client(query_range: payload), custom) do
      rows = custom.range("up", start_time: 0, end_time: 200, step: "60s")
      assert_equal 12.5, rows.first["mem_mb"]
      assert_nil rows.first["value"]
    end
  end

  private

  # Captures Rails.logger output for the duration of the block, then restores it.
  def with_log_io
    io = StringIO.new
    prior = Rails.logger
    Rails.logger = Logger.new(io)
    yield io
  ensure
    Rails.logger = prior
  end

  # Injects a fake gem client (the real one is memoized under @client).
  def with_client(fake, service = @service)
    prior = service.instance_variable_get(:@client)
    service.instance_variable_set(:@client, fake)
    yield
  ensure
    service.instance_variable_set(:@client, prior)
  end
end
