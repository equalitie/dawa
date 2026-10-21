require "test_helper"

#
# Tests for the log-explorer filter state.
#
# This object is the server half of Step 4's split: the browser owns filter *state*, but
# only the server turns it into a query. Everything here is untrusted input arriving via
# the query string (or echoed back by the client), so the validation rules are the point.
#
class Logs::FiltersTest < ActiveSupport::TestCase
  ##
  ## defaults and validation
  ##

  test "defaults to the default range and no filters" do
    filters = Logs::Filters.new({})

    assert_equal Logs::Filters::DEFAULT_RANGE, filters.range
    assert_nil filters.host
    assert_nil filters.programname
    assert_nil filters.severity
    assert_nil filters.text
    refute filters.filtered?
  end

  test "accepts an allow-listed range" do
    assert_equal "24h", Logs::Filters.new(range: "24h").range
  end

  test "rejects an unknown range instead of passing it through" do
    # An arbitrary range would end up verbatim in the `_time:` filter.
    assert_equal Logs::Filters::DEFAULT_RANGE, Logs::Filters.new(range: "99y").range
    assert_equal Logs::Filters::DEFAULT_RANGE, Logs::Filters.new(range: "1h AND _msg:secret").range
  end

  test "strips surrounding whitespace from filter values" do
    assert_equal "tern", Logs::Filters.new(host: "  tern  ").host
  end

  test "treats blank values as unset" do
    filters = Logs::Filters.new(host: "", programname: "   ")

    assert_nil filters.host
    assert_nil filters.programname
    refute filters.filtered?
  end

  test "rejects array and hash values rather than picking one" do
    # `?host=a&host=b` must not silently become a filter nobody asked for.
    assert_nil Logs::Filters.new(host: %w[a b]).host
    assert_nil Logs::Filters.new(host: { "a" => "b" }).host
  end

  test "truncates an over-long free-text term" do
    filters = Logs::Filters.new(text: "x" * 500)

    assert_equal Logs::Filters::MAX_TEXT_LENGTH, filters.text.length
  end

  test "reads ActionController::Parameters without needing them permitted" do
    # `params.to_h` raises UnfilteredParameters; only known keys are read, so unknown
    # params are irrelevant by construction.
    params = ActionController::Parameters.new(host: "tern", unexpected: "value")

    assert_equal "tern", Logs::Filters.new(params).host
  end

  ##
  ## filtered?
  ##

  test "filtered? is true when any filter is set" do
    assert Logs::Filters.new(host: "tern").filtered?
    assert Logs::Filters.new(programname: "sshd").filtered?
    assert Logs::Filters.new(severity: "err").filtered?
    assert Logs::Filters.new(text: "failed").filtered?
  end

  test "filtered? ignores the range" do
    # A time window is not a "filter" in the sense the empty state cares about: changing
    # it never explains why a search returned nothing.
    refute Logs::Filters.new(range: "7d").filtered?
  end

  ##
  ## field_filters
  ##

  test "field_filters are empty when nothing is set" do
    assert_equal [], Logs::Filters.new({}).field_filters
  end

  test "field_filters are emitted in a fixed order" do
    filters = Logs::Filters.new(severity: "err", host: "tern", programname: "sshd")

    assert_equal [ 'host:"tern"', 'programname:"sshd"', 'severity:"err"' ], filters.field_filters
  end

  test "every filter term is accepted" do
    Logs::FieldCatalog::SEVERITY_FILTER_TERMS.each do |term|
      assert_equal term, Logs::Filters.new(severity: term).severity
    end
  end

  test "a group term expands to a union of its levels" do
    # `crit` covers crit/alert/emerg. The expansion lives in the catalog, so a change to the
    # grouping changes the query without touching this class.
    assert_equal %w[crit alert emerg], Logs::FieldCatalog.severity_levels_for("crit")
    assert_equal 'severity:"err"', Logs::Filters.new(severity: "err").severity_filter
    assert_equal '(severity:"crit" OR severity:"alert" OR severity:"emerg")',
                 Logs::Filters.new(severity: "crit").severity_filter
  end

  test "individual critical levels are not accepted as terms" do
    # They are covered by the `crit` group, and offering them separately is what the grouping
    # exists to avoid, so typing one by hand is dropped rather than silently matching.
    %w[emerg alert].each do |level|
      assert_nil Logs::Filters.new(severity: level).severity
    end
  end

  test "an unknown severity is dropped rather than passed through" do
    # Severity is a closed set (the names `to_syslog_level` emits), not free-form like a
    # hostname. Emitting a `severity:` filter that matches nothing is worse than no filter:
    # the empty result reads as "no errors" rather than "you asked a bad question".
    filters = Logs::Filters.new(severity: "not-a-level")

    assert_nil filters.severity
    refute filters.filtered?
    assert_equal [], filters.field_filters
  end

  test "severity validation is case-insensitive" do
    assert_equal "err", Logs::Filters.new(severity: "ERR").severity
  end

  test "severity validation rejects non-scalars" do
    # A repeated param (`?severity=a&severity=b`) should not silently become a filter.
    assert_nil Logs::Filters.new(severity: [ "err", "crit" ]).severity
    assert_nil Logs::Filters.new(severity: { "a" => "b" }).severity
  end

  test "field_filters quote values so punctuation cannot break the expression" do
    filters = Logs::Filters.new(host: 'ter n AND _msg:"secret"')

    assert_equal [ 'host:"ter n AND _msg:\\"secret\\""' ], filters.field_filters
  end

  ##
  ## to_params
  ##

  test "to_params round-trips the state" do
    params = Logs::Filters.new(host: "tern", text: "failed", range: "6h").to_params

    assert_equal "tern", params["host"]
    assert_equal "failed", params["text"]
    assert_equal "6h", params["range"]
  end

  test "to_params drops blank values so URLs stay clean" do
    refute Logs::Filters.new({}).to_params.key?("host")
  end

  test "to_params accepts symbol or string overrides" do
    filters = Logs::Filters.new({})

    assert_equal "24h", filters.to_params(range: "24h")["range"]
    assert_equal "24h", filters.to_params("range" => "24h")["range"]
  end

  test "to_params overrides an existing value" do
    filters = Logs::Filters.new(range: "1h")

    assert_equal "7d", filters.to_params(range: "7d")["range"]
  end

  test "is indifferent to symbol and string keys" do
    # The page passes params; the endpoint may pass a parsed JSON body.
    assert_equal "tern", Logs::Filters.new("host" => "tern").host
    assert_equal "tern", Logs::Filters.new(host: "tern").host
  end

  test "to_params always carries the range" do
    # The range is part of the state even when it is the default, so a refresh URL is
    # unambiguous about the window it is asking for.
    assert_equal Logs::Filters::DEFAULT_RANGE, Logs::Filters.new({}).to_params["range"]
  end

  test "to_params round-trips through a real query string" do
    # The refresh URL is built this way, so the encoding must survive.
    params = Logs::Filters.new(host: "ter n", text: "a&b").to_params

    assert_equal [ [ "host", "ter n" ], [ "text", "a&b" ] ],
                 URI.decode_www_form(params.to_query).reject { |k, _| k == "range" }
  end

  ##
  ## parse_cursor
  ##

  test "parse_cursor accepts an RFC3339 instant" do
    cursor = Logs::Filters.parse_cursor("2026-09-08T00:59:13.000000Z")

    assert_equal Time.zone.parse("2026-09-08T00:59:13Z"), cursor
  end

  test "parse_cursor accepts an offset form" do
    refute_nil Logs::Filters.parse_cursor("2026-09-08T00:59:13-07:00")
  end

  test "parse_cursor rejects anything it cannot trust" do
    # The cursor is echoed back by the client, so it must not reach LogsQL unchecked.
    assert_nil Logs::Filters.parse_cursor("not-a-timestamp")
    assert_nil Logs::Filters.parse_cursor("")
    assert_nil Logs::Filters.parse_cursor(nil)
    assert_nil Logs::Filters.parse_cursor('_msg:"secret"')
    assert_nil Logs::Filters.parse_cursor("2026-09-08")
  end
end
