require_relative "../test_helper"

#
# Integration tests for the read-only host-log view backed by VictoriaLogs. The
# service is stubbed so these run without a live VictoriaLogs instance.
#
class LogsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "logs-test-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  # Replace the controller's VictoriaLogs service with a stub that returns the given
  # records (or raises, to exercise the unreachable path).
  def with_stubbed_service(records: [], raises: nil, recorded: nil)
    fake = Object.new
    fake.define_singleton_method(:query_lines) do |query = "", **kwargs|
      recorded&.replace([ query, kwargs ])
      raise raises if raises
      records
    end

    LogsController.define_method(:service) { fake }
    yield
  ensure
    LogsController.send(:remove_method, :service)
  end

  def sample_records
    [
      { "_time" => "2026-09-08T00:59:12Z", "_stream" => "{host=\"tern\",programname=\"sshd\"}", "host" => "tern", "programname" => "sshd", "unit" => "ssh.service", "severity" => "info", "_msg" => "Accepted publickey for admin" },
      { "_time" => "2026-09-08T00:59:13Z", "_stream" => "{host=\"tern\",programname=\"cron\"}", "host" => "tern", "programname" => "cron", "unit" => "cron.service", "severity" => "info", "_msg" => "session opened" }
    ]
  end

  def test_index_requires_admin
    get logs_path
    assert_response :redirect
    assert_redirected_to login_path
  end

  test "index_renders_records" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_response :success
    assert_select "td", text: /sshd/
    assert_select "code", text: /Accepted publickey/
    assert_select "code", text: /session opened/
    # the time-range selector reflects the default window
    assert_select "button", text: /#{I18n.t("logs.index.range.#{LogsHelper::DEFAULT_RANGE}")}/
    # each record exposes its full JSON
    assert_select "details summary", text: "JSON"
  end

  test "index rows carry the dedupe key" do
    # The refresh controller seeds its "already shown" set from these attributes. Without
    # them it would re-append every row currently on the page on the first poll.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "tr[data-row-key]", count: 2
  end

  ##
  ## pause / resume control
  ##

  test "the pause control starts with pause visible and resume hidden" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "button[data-logs-explorer-target='pauseButton']" do |buttons|
      refute buttons.first["hidden"], "pause must be visible while polling"
    end
    assert_select "button[data-logs-explorer-target='resumeButton'][hidden]"
  end

  test "pause and resume are hidden with the hidden attribute, not an inline style" do
    # The controller toggles `.hidden` (the property/attribute). Its counterpart on the
    # server must use the SAME mechanism: an inline `display: none` survives
    # `.hidden = false`, so the Resume button would never reappear and the pause button
    # would simply vanish. `hide: true` now emits `hidden`, so this pins that contract.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "button[data-logs-explorer-target='resumeButton'][hidden]"
    assert_select "button[data-logs-explorer-target='resumeButton']" do |buttons|
      refute_includes buttons.first["style"].to_s, "display:",
                      "hiding must not rely on an inline display style"
    end
  end

  test "the disconnected badge starts hidden the same way" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "[data-logs-explorer-target='status'][hidden]"
  end

  test "server-rendered row keys match the json endpoint" do
    # The two must agree on identity, or a polled row would duplicate one already on the
    # page.
    keys_from_html = []
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
      keys_from_html = response.body.scan(/data-row-key="([^"]*)"/).flatten.map { |k| CGI.unescapeHTML(k) }

      get data_logs_path
    end

    keys_from_json = JSON.parse(response.body)["rows"].map { |r| r["key"] }
    assert_equal keys_from_html.sort, keys_from_json.sort
  end

  def test_index_requests_the_configured_default_limit_and_default_range
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get logs_path
    end

    query, kwargs = recorded
    # Default range is the last hour, expressed as a LogsQL `_time:` filter.
    assert_equal "_time:#{LogsHelper::DEFAULT_RANGE}", query
    assert_equal Conf.logs_default_limit, kwargs[:limit]
  end

  def test_index_applies_the_selected_range
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get logs_path(range: "24h")
    end

    assert_equal "_time:24h", recorded.first
  end

  def test_index_ignores_an_unknown_range_value
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get logs_path(range: "99y")
    end

    assert_equal "_time:#{LogsHelper::DEFAULT_RANGE}", recorded.first
  end

  def test_index_renders_empty_state_when_there_are_no_logs
    with_stubbed_service(records: []) do
      login_as(@user)
      get logs_path
    end

    assert_response :success
    # The empty state is an alert, not a table row: with no rows there is no table at all,
    # and the wording must not imply the filters caused the emptiness.
    assert_select ".alert-info", text: /No logs have been received/
  end

  def test_index_distinguishes_no_matches_from_no_logs
    # "nothing matched your filters" and "there are no logs" call for different next
    # actions, so the empty state must not conflate them.
    #
    # NOTE: the filter goes in an explicit query string. `logs_path(host: "tern")` silently
    # returns a bare `/logs`, because route helpers drop params that are not route segments.
    with_stubbed_service(records: []) do
      login_as(@user)
      get "#{logs_path}?host=tern"
    end

    assert_response :success
    assert_select ".alert-info", text: /No logs matched these filters/
    assert_no_match(/No logs have been received/, response.body)
  end

  def test_index_renders_warning_banner_when_victorialogs_is_unreachable
    with_stubbed_service(raises: VictoriaLogs::RequestError.new("VictoriaLogs request failed: 500")) do
      login_as(@user)
      get logs_path
    end

    assert_response :success
    assert_select ".alert-danger"
    assert_select ".alert-danger", text: /VictoriaLogs/
  end

  def test_index_does_not_500_on_connection_failure
    with_stubbed_service(raises: Faraday::ConnectionFailed.new("connection refused")) do
      login_as(@user)
      get logs_path
    end

    assert_response :success
    assert_select ".alert-danger"
  end

  #
  # data (JSON refresh, Step 4)
  #

  def test_data_requires_admin
    get data_logs_path
    assert_response :redirect
    assert_redirected_to login_path
  end

  def test_data_returns_json_rows_with_the_display_fields_preformatted
    # The client renders rows from these strings rather than re-deriving them, so a live
    # row is formatted by the same Ruby that formatted the initial page.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 2, body["rows"].size

    row = body["rows"].first
    assert_equal "sshd", row["source"]
    assert_equal "Accepted publickey for admin", row["message"]
    assert row["time_display"].present?, "time must be preformatted server-side"
    assert row["key"].present?, "a row key is required for client-side dedupe"
    assert row["json"].present?
  end

  def test_data_row_keys_are_stable_and_content_derived
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
      first = JSON.parse(response.body)["rows"].map { |r| r["key"] }

      get data_logs_path
      second = JSON.parse(response.body)["rows"].map { |r| r["key"] }

      assert_equal first, second, "keys must not change between polls"
      assert_equal first.uniq, first, "keys must be distinct within a batch"
    end
  end

  def test_data_keys_distinguish_records_sharing_a_timestamp
    # Several logs can share a `_time` (syslog bursts, journald). Keying on time alone
    # would make the client discard real rows as duplicates.
    records = [
      { "_time" => "2026-09-08T00:59:12Z", "_stream_id" => "s1", "_msg" => "first" },
      { "_time" => "2026-09-08T00:59:12Z", "_stream_id" => "s1", "_msg" => "second" }
    ]

    with_stubbed_service(records: records) do
      login_as(@user)
      get data_logs_path
    end

    keys = JSON.parse(response.body)["rows"].map { |r| r["key"] }
    assert_equal 2, keys.uniq.size
  end

  def test_data_returns_the_newest_time_as_the_next_cursor
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
    end

    cursor = JSON.parse(response.body)["cursor"]
    assert_equal Time.zone.parse("2026-09-08T00:59:13Z").utc.iso8601(6), cursor
  end

  def test_data_polls_only_newer_logs_when_given_a_cursor
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get "#{data_logs_path}?cursor=2026-09-08T00:59:13.000000Z"
    end

    query, = recorded
    # Half-open on the left: the browser already holds the row at exactly the cursor, so
    # including it would re-send that row on every poll.
    assert_equal "_time:(2026-09-08T00:59:13.000000Z, now]", query
  end

  def test_data_replaces_the_range_with_the_cursor_window
    # The cursor is the more specific bound, so the window is not also applied.
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get "#{data_logs_path}?range=24h&cursor=2026-09-08T00:59:13.000000Z"
    end

    query, = recorded
    assert_includes query, "_time:("
    refute_includes query, "_time:24h"
  end

  def test_data_ignores_a_malformed_cursor_and_falls_back_to_the_window
    # The cursor is echoed back by the client, so it is untrusted. A junk value must not
    # reach LogsQL.
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get "#{data_logs_path}?range=6h&cursor=not-a-timestamp"
    end

    assert_equal "_time:6h", recorded.first
  end

  def test_data_ignores_a_cursor_in_the_future
    # Clock skew (or a hand-edited value) could put the cursor ahead of the server, making
    # the interval empty-to-invalid. Falling back to the window shows something instead.
    recorded = []
    future = (Time.now.utc + 1.day).iso8601(6)

    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get "#{data_logs_path}?range=1h&cursor=#{ERB::Util.url_encode(future)}"
    end

    assert_equal "_time:1h", recorded.first
  end

  def test_data_applies_filters_to_the_query
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get "#{data_logs_path}?host=tern&programname=sshd&text=failed"
    end

    query, = recorded
    assert_includes query, 'host:"tern"'
    assert_includes query, 'programname:"sshd"'
    assert_includes query, '"failed"'
  end

  def test_data_reports_a_backend_failure_as_an_error_not_an_empty_batch
    # If a refresh failure returned `rows: []`, an outage would be indistinguishable from
    # a quiet log -- the one thing a sysadmin most needs to notice.
    with_stubbed_service(raises: VictoriaLogs::RequestError.new("VictoriaLogs request failed: 500")) do
      login_as(@user)
      get data_logs_path
    end

    assert_response :bad_gateway
    body = JSON.parse(response.body)
    assert_equal [], body["rows"]
    assert_match(/VictoriaLogs/, body["error"])
  end

  def test_data_returns_an_empty_batch_when_there_are_no_new_logs
    with_stubbed_service(records: []) do
      login_as(@user)
      get "#{data_logs_path}?cursor=2026-09-08T00:59:13.000000Z"
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["rows"]
    assert_equal 0, body["count"]
    assert_nil body["error"]
  end

  def test_index_seeds_the_cursor_from_the_newest_rendered_row
    # Without this the first poll would refetch the whole window.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "[data-logs-explorer-cursor-value='#{Time.zone.parse("2026-09-08T00:59:13Z").utc.iso8601(6)}']"
  end
end
