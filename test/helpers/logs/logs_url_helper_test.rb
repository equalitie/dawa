require "test_helper"

#
# Tests for the log-explorer URL helpers.
#
# The interesting case is `host`, which collides with a reserved URL option on Rails' route
# helpers. These tests exist so that collision is recorded as behaviour rather than
# rediscovered (and mis-explained) later.
#
# Named distinctly from Logs::HelperTest (test/helpers/logs/helper_test.rb): two test classes
# sharing a name would silently reopen each other.
#
class Logs::UrlHelperTest < ActionView::TestCase
  include Logs::Helper

  ##
  ## the route-helper collision this helper works around
  ##

  test "a symbol host is consumed by the route helper and never emitted" do
    # `host:` is the URL option that sets the request host, so a SYMBOL key is consumed.
    # This is why `logs_path_with` exists: our `host` filter is a real field name.
    assert_equal "/logs", logs_path(host: "tern")
  end

  test "a string host becomes a query param on the route helper" do
    # The same value under a string key is not recognized as the URL option.
    assert_equal "/logs?host=tern", logs_path({ "host" => "tern" })
  end

  test "a symbol host is dropped while its sibling filters survive" do
    # The failure mode is silent: the URL looks plausible and only the host filter is gone.
    assert_equal "/logs?range=24h", logs_path(range: "24h", host: "tern")
  end

  test "other filter keys are unaffected by the collision" do
    # Guards the claim that `host` is special rather than route helpers dropping unknown
    # params (they do not).
    assert_equal "/logs?text=failed", logs_path(text: "failed")
    assert_equal "/logs?programname=sshd", logs_path(programname: "sshd")
    assert_equal "/logs?absent=1", logs_path(absent: "1")
  end

  ##
  ## logs_path_with
  ##

  test "logs_path_with preserves a host filter" do
    filters = LogsFilters.new(host: "tern")

    assert_equal "/logs?host=tern&range=#{LogsFilters::DEFAULT_RANGE}", logs_path_with({}, filters: filters)
  end

  test "logs_path_with preserves every filter at once" do
    filters = LogsFilters.new(
      range: "6h", host: "tern", programname: "sshd", severity: "err", text: "failed login"
    )

    path = logs_path_with({}, filters: filters)
    query = URI.decode_www_form(URI.parse(path).query).to_h

    assert_equal "6h", query["range"]
    assert_equal "tern", query["host"]
    assert_equal "sshd", query["programname"]
    assert_equal "err", query["severity"]
    assert_equal "failed login", query["text"]
  end

  test "logs_path_with applies an override" do
    filters = LogsFilters.new(host: "tern", range: "1h")

    query = URI.decode_www_form(URI.parse(logs_path_with({ range: "7d" }, filters: filters)).query).to_h

    assert_equal "7d", query["range"]
    assert_equal "tern", query["host"], "overriding the range must not drop other filters"
  end

  test "logs_path_with emits a bare path when there are no filters" do
    # `range` is always present, so drive this through a filters object with no overrides
    # and no state: the default range still appears, and nothing is duplicated.
    path = logs_path_with({}, filters: LogsFilters.new)

    assert_equal "/logs?range=#{LogsFilters::DEFAULT_RANGE}", path
  end

  test "logs_path_with escapes values that need it" do
    filters = LogsFilters.new(text: "a&b=c", host: "ter n")

    query = URI.decode_www_form(URI.parse(logs_path_with({}, filters: filters)).query).to_h

    assert_equal "a&b=c", query["text"]
    assert_equal "ter n", query["host"]
  end

  ##
  ## logs_refresh_path
  ##

  test "logs_refresh_path points at the json endpoint and carries the filters" do
    filters = LogsFilters.new(host: "tern", range: "24h")

    query = URI.decode_www_form(URI.parse(logs_refresh_path(filters)).query).to_h

    assert_equal "/logs/data", URI.parse(logs_refresh_path(filters)).path
    assert_equal "tern", query["host"]
    assert_equal "24h", query["range"]
  end

  test "logs_refresh_path preserves the host filter despite the route-helper collision" do
    # The endpoint URL is the one the Stimulus controller polls, so a dropped `host` would
    # silently refresh unfiltered logs.
    assert_includes logs_refresh_path(LogsFilters.new(host: "tern")), "host=tern"
  end
end
