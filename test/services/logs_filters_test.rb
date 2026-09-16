require "test_helper"

#
# Tests for the log-explorer filter state.
#
# This object is the server half of Step 4's split: the browser owns filter *state*, but
# only the server turns it into a query. Everything here is untrusted input arriving via
# the query string (or echoed back by the client), so the validation rules are the point.
#
class LogsFiltersTest < ActiveSupport::TestCase
  ##
  ## defaults and validation
  ##

  test "defaults to the default range and no filters" do
    filters = LogsFilters.new({})

    assert_equal LogsFilters::DEFAULT_RANGE, filters.range
    assert_nil filters.host
    assert_nil filters.programname
    assert_nil filters.severity
    assert_nil filters.text
    refute filters.filtered?
  end

  test "accepts an allow-listed range" do
    assert_equal "24h", LogsFilters.new(range: "24h").range
  end

  test "rejects an unknown range instead of passing it through" do
    # An arbitrary range would end up verbatim in the `_time:` filter.
    assert_equal LogsFilters::DEFAULT_RANGE, LogsFilters.new(range: "99y").range
    assert_equal LogsFilters::DEFAULT_RANGE, LogsFilters.new(range: "1h AND _msg:secret").range
  end

  test "strips surrounding whitespace from filter values" do
    assert_equal "tern", LogsFilters.new(host: "  tern  ").host
  end

  test "treats blank values as unset" do
    filters = LogsFilters.new(host: "", programname: "   ")

    assert_nil filters.host
    assert_nil filters.programname
    refute filters.filtered?
  end

  test "rejects array and hash values rather than picking one" do
    # `?host=a&host=b` must not silently become a filter nobody asked for.
    assert_nil LogsFilters.new(host: %w[a b]).host
    assert_nil LogsFilters.new(host: { "a" => "b" }).host
  end

  test "truncates an over-long free-text term" do
    filters = LogsFilters.new(text: "x" * 500)

    assert_equal LogsFilters::MAX_TEXT_LENGTH, filters.text.length
  end

  test "reads ActionController::Parameters without needing them permitted" do
    # `params.to_h` raises UnfilteredParameters; only known keys are read, so unknown
    # params are irrelevant by construction.
    params = ActionController::Parameters.new(host: "tern", unexpected: "value")

    assert_equal "tern", LogsFilters.new(params).host
  end

  ##
  ## filtered?
  ##

  test "filtered? is true when any filter is set" do
    assert LogsFilters.new(host: "tern").filtered?
    assert LogsFilters.new(programname: "sshd").filtered?
    assert LogsFilters.new(severity: "err").filtered?
    assert LogsFilters.new(text: "failed").filtered?
  end

  test "filtered? ignores the range" do
    # A time window is not a "filter" in the sense the empty state cares about: changing
    # it never explains why a search returned nothing.
    refute LogsFilters.new(range: "7d").filtered?
  end

  ##
  ## field_filters
  ##

  test "field_filters are empty when nothing is set" do
    assert_equal [], LogsFilters.new({}).field_filters
  end

  test "field_filters are emitted in a fixed order" do
    filters = LogsFilters.new(severity: "err", host: "tern", programname: "sshd")

    assert_equal [ 'host:"tern"', 'programname:"sshd"', 'severity:"err"' ], filters.field_filters
  end

  test "field_filters quote values so punctuation cannot break the expression" do
    filters = LogsFilters.new(host: 'ter n AND _msg:"secret"')

    assert_equal [ 'host:"ter n AND _msg:\\"secret\\""' ], filters.field_filters
  end

  ##
  ## to_params
  ##

  test "to_params round-trips the state" do
    params = LogsFilters.new(host: "tern", text: "failed", range: "6h").to_params

    assert_equal "tern", params["host"]
    assert_equal "failed", params["text"]
    assert_equal "6h", params["range"]
  end

  test "to_params drops blank values so URLs stay clean" do
    refute LogsFilters.new({}).to_params.key?("host")
  end

  test "to_params accepts symbol or string overrides" do
    filters = LogsFilters.new({})

    assert_equal "24h", filters.to_params(range: "24h")["range"]
    assert_equal "24h", filters.to_params("range" => "24h")["range"]
  end

  test "to_params overrides an existing value" do
    filters = LogsFilters.new(range: "1h")

    assert_equal "7d", filters.to_params(range: "7d")["range"]
  end

  test "is indifferent to symbol and string keys" do
    # The page passes params; the endpoint may pass a parsed JSON body.
    assert_equal "tern", LogsFilters.new("host" => "tern").host
    assert_equal "tern", LogsFilters.new(host: "tern").host
  end

  test "to_params always carries the range" do
    # The range is part of the state even when it is the default, so a refresh URL is
    # unambiguous about the window it is asking for.
    assert_equal LogsFilters::DEFAULT_RANGE, LogsFilters.new({}).to_params["range"]
  end

  test "to_params round-trips through a real query string" do
    # The refresh URL is built this way, so the encoding must survive.
    params = LogsFilters.new(host: "ter n", text: "a&b").to_params

    assert_equal [ [ "host", "ter n" ], [ "text", "a&b" ] ],
                 URI.decode_www_form(params.to_query).reject { |k, _| k == "range" }
  end

  ##
  ## parse_cursor
  ##

  test "parse_cursor accepts an RFC3339 instant" do
    cursor = LogsFilters.parse_cursor("2026-09-08T00:59:13.000000Z")

    assert_equal Time.zone.parse("2026-09-08T00:59:13Z"), cursor
  end

  test "parse_cursor accepts an offset form" do
    refute_nil LogsFilters.parse_cursor("2026-09-08T00:59:13-07:00")
  end

  test "parse_cursor rejects anything it cannot trust" do
    # The cursor is echoed back by the client, so it must not reach LogsQL unchecked.
    assert_nil LogsFilters.parse_cursor("not-a-timestamp")
    assert_nil LogsFilters.parse_cursor("")
    assert_nil LogsFilters.parse_cursor(nil)
    assert_nil LogsFilters.parse_cursor('_msg:"secret"')
    assert_nil LogsFilters.parse_cursor("2026-09-08")
  end
end
