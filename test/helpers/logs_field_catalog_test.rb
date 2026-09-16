require "test_helper"

#
# Gate test for the shared log field catalog.
#
# The catalog is the single source of truth for display columns and (later) facet
# suggestions. Besides basic shape checks, this reconciles the catalog against the
# fields a live deployment actually emits — but only when VictoriaLogs is reachable,
# so the suite stays green offline (the reconciliation is the point of the gate when a
# backend is present).
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

  test "catalog matches the fields a live host log actually emits" do
    fields = live_host_field_names
    skip "VictoriaLogs not reachable" if fields.nil?

    missing_from_catalog = fields.map(&:to_sym) - LogsFieldCatalog::HOST_FIELDS - controllable_extra_fields
    unexpected_in_catalog = LogsFieldCatalog::HOST_FIELDS.map(&:to_s) - fields

    assert_empty missing_from_catalog,
                 "live host logs emit fields not in the catalog: #{missing_from_catalog.inspect}"
    assert_empty unexpected_in_catalog,
                 "catalog lists fields the live host logs never emit: #{unexpected_in_catalog.inspect}"
  end

  private

  # Fields that may legitimately appear on a record but aren't catalog columns (they
  # render as expandable "other" fields / in the JSON). Host logs are normalized by the
  # `parse_host_logs` transform; `_stream`/`_stream_id` are always present, and journald
  # records carry a lot of extra metadata (`SYSLOG_FACILITY`, `_PID`, `__REALTIME_TIMESTAMP`,
  # ...) which we surface as "other" columns rather than promoted to the canonical set.
  def controllable_extra_fields
    [ :_stream, :_stream_id, :source_type, :program, :facility, :message, :timestamp,
      :SYSLOG_FACILITY, :SYSLOG_PID, :SYSLOG_TIMESTAMP, :_BOOT_ID, :_MACHINE_ID, :_RUNTIME_SCOPE,
      :_SOURCE_BOOTTIME_TIMESTAMP, :_SOURCE_MONOTONIC_TIMESTAMP, :_SOURCE_REALTIME_TIMESTAMP,
      :_TRANSPORT, :_GID, :_UID, :_PID, :_CAP_EFFECTIVE, :_CMDLINE, :_COMM, :_EXE,
      :_SYSTEMD_CGROUP, :_SYSTEMD_INVOCATION_ID, :_SYSTEMD_SLICE,
      :__MONOTONIC_TIMESTAMP, :__REALTIME_TIMESTAMP, :__SEQNUM, :__SEQNUM_ID ]
  end

  # Ask a live VictoriaLogs for the field names in the last hour, or nil if unreachable.
  def live_host_field_names
    VictoriaLogs.new.field_names("_time:1h")
  rescue VictoriaLogs::RequestError, Faraday::Error
    nil
  end
end
