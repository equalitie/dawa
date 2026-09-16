require "test_helper"

#
# Gate test for the shared log field catalog.
#
# The catalog is the single source of truth for display columns and (later) facet
# suggestions. Besides basic shape checks, this reconciles the catalog against the
# fields a live deployment actually emits -- but only when VictoriaLogs is reachable,
# so the suite stays green offline (the reconciliation is the point of the gate when a
# backend is present).
#
# The reconciliation is one-directional on purpose. Journald records carry an open-ended
# set of per-program structured fields, so asserting that the live field set is "known"
# would fail on every package update. What matters is that the catalog never lists a
# field the deployment doesn't emit, and that the always-rendered fields are present.
#
class LogsFieldCatalogTest < ActiveSupport::TestCase
  test "host fields are non-empty, ordered, and unique" do
    fields = LogsFieldCatalog::HOST_FIELDS
    assert fields.any?
    assert_equal fields.uniq, fields, "no duplicate fields in the catalog"
    assert_includes fields, :_time
    assert_includes fields, :_msg
  end

  test "displayable? and filterable? agree with the catalog membership" do
    assert LogsFieldCatalog.displayable?(:_time)
    assert LogsFieldCatalog.displayable?("_msg")
    assert LogsFieldCatalog.displayable?(:host)
    refute LogsFieldCatalog.displayable?(:dc_app), "container fields are Phase B"
    assert LogsFieldCatalog.filterable?(:host)
    assert LogsFieldCatalog.filterable?(:programname)
    assert LogsFieldCatalog.filterable?(:severity)
    refute LogsFieldCatalog.filterable?(:_msg)
  end

  test "unknown tiers expose no fields" do
    assert_equal [], LogsFieldCatalog.known(:bogus)
    assert_equal [], LogsFieldCatalog.filterable(:bogus)
    refute LogsFieldCatalog.displayable?(:_time, tier: :bogus)
  end

  test "catalog fields are all emitted by live host logs" do
    fields = live_field_names
    skip "VictoriaLogs not reachable" if fields.nil?

    # Only this direction is a real invariant: the catalog must not list fields the
    # deployment never emits (that would be a fabricated column).
    #
    # The reverse direction is deliberately NOT asserted. Journald records carry
    # arbitrary per-program structured fields (`NM_LOG_DOMAINS` from NetworkManager,
    # `GLIB_DOMAIN`, `CPU_USAGE_NSEC`, `_AUDIT_SESSION`, ...) whose set is open-ended
    # and grows with whatever software is installed. Asserting it is a closed set
    # would fail on every package update. Those fields surface as "other" columns and
    # in the JSON view, which is the intended behaviour.
    unexpected_in_catalog = LogsFieldCatalog::HOST_FIELDS.map(&:to_s) - fields

    assert_empty unexpected_in_catalog,
                 "catalog lists fields the live host logs never emit: #{unexpected_in_catalog.inspect}"
  end

  test "live host logs carry the fields the table always renders" do
    fields = live_field_names&.map(&:to_s)
    skip "VictoriaLogs not reachable" if fields.nil?

    # The presenter renders these for every row, so their absence is a real bug (a
    # misconfigured parse transform, say), unlike arbitrary extra metadata.
    required = %w[_time _msg]

    assert_empty required - fields,
                 "live host logs are missing required fields: #{(required - fields).inspect}"
  end

  private

  # Ask a live VictoriaLogs for the field names in the last hour, or nil if unreachable.
  def live_field_names
    VictoriaLogs.new.field_names("_time:1h")
  rescue VictoriaLogs::RequestError, Faraday::Error
    nil
  end
end
