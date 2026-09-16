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

  def test_index_renders_records
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
    assert_select "tr#empty-row"
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
end
