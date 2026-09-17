require "test_helper"

#
# Unit tests for the VictoriaLogs service. The Faraday connection is stubbed so these
# run without a live VictoriaLogs instance; they pin the NDJSON parsing, request params,
# error handling, and the LogsQL expression builder.
#
class VictoriaLogsTest < ActiveSupport::TestCase
  setup do
    @service = VictoriaLogs.new
  end

  # A fake Faraday connection: records each [path, params] and returns a canned response
  # object (responding to #body).
  def fake_connection(status: 200, body: "")
    calls = []
    response = Object.new
    response.define_singleton_method(:body) { body }
    response.define_singleton_method(:status) { status }

    conn = Object.new
    conn.define_singleton_method(:calls) { calls }
    conn.define_singleton_method(:get) do |path, params = {}|
      calls << [ path, params ]
      response
    end
    conn
  end

  def with_connection(fake)
    prior = @service.instance_variable_get(:@connection)
    @service.instance_variable_set(:@connection, fake)
    yield
  ensure
    @service.instance_variable_set(:@connection, prior)
  end

  test "defaults url to the configured logs_url" do
    assert_equal "http://localhost:9428", @service.url
    assert_equal "http://example.test:9428", VictoriaLogs.new(url: "http://example.test:9428").url
  end

  test "parses an NDJSON body into records, preserving fields" do
    body = <<~NDJSON
      {"_time":"2026-09-08T00:59:12Z","_stream":"{host=\\"tern\\"}","programname":"sshd","_msg":"Accepted publickey"}
      {"_time":"2026-09-08T00:59:13Z","_stream":"{host=\\"tern\\"}","programname":"sshd","_msg":"Disconnected"}
    NDJSON

    with_connection(fake_connection(body: body)) do
      records = @service.query_lines("", limit: 10)
      assert_equal 2, records.size
      assert_equal "Accepted publickey", records[0]["_msg"]
      assert_equal "sshd", records[0]["programname"]
      assert_equal "2026-09-08T00:59:13Z", records[1]["_time"]
    end
  end

  test "skips blank/whitespace lines in the NDJSON body" do
    body = "\n{\"_msg\":\"one\"}\n   \n{\"_msg\":\"two\"}\n"

    with_connection(fake_connection(body: body)) do
      records = @service.query_lines("")
      assert_equal [ "one", "two" ], records.map { |r| r["_msg"] }
    end
  end

  test "returns an empty array for an empty body / no matches" do
    with_connection(fake_connection(body: "")) do
      assert_equal [], @service.query_lines("nothing")
    end
  end

  test "sends the query, limit and offset to the query endpoint" do
    fake = fake_connection(body: "")
    with_connection(fake) do
      @service.query_lines("level:error", limit: 50, offset: 100)
      path, params = fake.calls.last
      assert_equal "/select/logsql/query", path
      assert_equal "level:error", params[:query]
      assert_equal 50, params[:limit]
      assert_equal 100, params[:offset]
    end
  end

  test "omits limit/offset when not supplied" do
    fake = fake_connection(body: "")
    with_connection(fake) do
      @service.query_lines("all")
      _path, params = fake.calls.last
      assert_equal({ query: "all" }, params)
    end
  end

  test "raises RequestError on malformed NDJSON" do
    with_connection(fake_connection(body: "not json\n")) do
      assert_raises(VictoriaLogs::RequestError) { @service.query_lines("") }
    end
  end

  test "wraps a non-2xx Faraday response as RequestError" do
    fake = Object.new
    fake.define_singleton_method(:get) do |_path, _params = {}|
      raise Faraday::ServerError.new("boom", { status: 500 })
    end

    with_connection(fake) do
      assert_raises(VictoriaLogs::RequestError) { @service.query_lines("") }
    end
  end

  test "lets connection-level Faraday errors surface distinctly (unreachable)" do
    fake = Object.new
    fake.define_singleton_method(:get) do |_path, _params = {}|
      raise Faraday::ConnectionFailed.new("connection refused")
    end

    with_connection(fake) do
      assert_raises(Faraday::ConnectionFailed) { @service.query_lines("") }
    end
  end

  test "field_names parses the values/hits envelope into field names" do
    body = { values: [ { value: "_msg", hits: 10 }, { value: "programname", hits: 4 } ] }.to_json

    with_connection(fake_connection(body: body)) do
      assert_equal %w[_msg programname], @service.field_names
    end
  end

  test "field_names always sends a query param, because VictoriaLogs rejects a bare call" do
    # VictoriaLogs answers 400 to /select/logsql/field_names with no `query` arg at all, so
    # omitting it turns a working instance into an apparent outage. An empty query ("") is
    # sent rather than dropping the param.
    fake = fake_connection(body: { values: [] }.to_json)

    with_connection(fake) do
      @service.field_names
      path, params = fake.calls.last
      assert_equal "/select/logsql/field_names", path
      assert_equal "", params[:query]

      @service.field_names("*")
      _path, params = fake.calls.last
      assert_equal "*", params[:query]
    end
  end

  test "streams always sends a query param" do
    fake = fake_connection(body: "")

    with_connection(fake) do
      @service.streams
      _path, params = fake.calls.last
      assert_equal "", params[:query]
    end
  end

  test "streams parses NDJSON stream objects" do
    body = <<~NDJSON
      {"host":"tern","programname":"sshd","_stream_id":"abc"}
      {"host":"tern","programname":"cron","_stream_id":"def"}
    NDJSON

    with_connection(fake_connection(body: body)) do
      streams = @service.streams
      assert_equal 2, streams.size
      assert_equal "sshd", streams[0]["programname"]
    end
  end

  test "build_query composes field filters, a quoted term and a time range" do
    assert_equal 'level:error "failed login" _time:1h',
                 VictoriaLogs.build_query(field_filters: [ "level:error" ], text: "failed login", time_range: "1h")
  end

  test "build_query ANDs multiple field filters in order" do
    assert_equal "programname:sshd level:warning",
                 VictoriaLogs.build_query(field_filters: [ "programname:sshd", "level:warning" ])
  end

  test "build_query escapes embedded quotes/backslashes in the free-text term" do
    assert_equal "\"say \\\"hi\\\" c:\\\\path\"",
                 VictoriaLogs.build_query(text: 'say "hi" c:\path')
  end

  test "build_query returns an empty string when there are no parts" do
    assert_equal "", VictoriaLogs.build_query
  end

  test "build_query drops blank field filters" do
    assert_equal "level:error", VictoriaLogs.build_query(field_filters: [ "", "  ", "level:error" ])
  end

  ##
  ## cursor (live polling)
  ##

  test "build_query turns a cursor into a half-open time interval" do
    # Half-open on the left: the browser already holds the row at exactly the cursor, so
    # including it would re-send that row on every poll.
    cursor = Time.utc(2026, 9, 8, 0, 59, 13)

    assert_equal "_time:(2026-09-08T00:59:13.000000Z, now]",
                 VictoriaLogs.build_query(cursor: cursor)
  end

  test "build_query keeps microsecond precision in the cursor" do
    # Truncating to seconds would re-fetch every row in that second on each poll.
    cursor = Time.utc(2026, 9, 8, 0, 59, 13, 123_456)

    assert_includes VictoriaLogs.build_query(cursor: cursor), "2026-09-08T00:59:13.123456Z"
  end

  test "build_query prefers the cursor over a time range" do
    # They are alternatives: intersecting them would only cost more.
    query = VictoriaLogs.build_query(time_range: "24h", cursor: Time.utc(2026, 9, 8, 0, 59, 13))

    assert_includes query, "_time:("
    refute_includes query, "_time:24h"
  end

  test "build_query keeps field filters and text alongside a cursor" do
    query = VictoriaLogs.build_query(
      field_filters: [ 'host:"tern"' ], text: "failed", cursor: Time.utc(2026, 9, 8, 0, 59, 13)
    )

    assert_equal 'host:"tern" "failed" _time:(2026-09-08T00:59:13.000000Z, now]', query
  end

  test "build_query renders the cursor in UTC regardless of the instant's zone" do
    # The client's cursor arrives as a parsed Time; VictoriaLogs compares instants, so the
    # rendering must not depend on the server's zone.
    utc = Time.utc(2026, 9, 8, 0, 59, 13)
    shifted = utc.in_time_zone("America/Los_Angeles") # 2026-09-07 local

    assert_equal VictoriaLogs.build_query(cursor: utc),
                 VictoriaLogs.build_query(cursor: shifted)
  end
end
