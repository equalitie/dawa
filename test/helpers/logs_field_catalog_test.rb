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

  ##
  ## severity presentation
  ##

  test "severity leads the columns" do
    # It renders as a colour stripe, so its value is the leftmost cue in the row.
    assert_equal :severity, LogsFieldCatalog::HOST_FIELDS.first
  end

  test "severity is the unlabelled column" do
    assert LogsFieldCatalog.unlabelled?(:severity)
    refute LogsFieldCatalog.unlabelled?(:_time)
  end

  test "every syslog level has a colour" do
    # `to_syslog_level` derives severity from journald's numeric PRIORITY (0..7), producing
    # exactly these names. A missing mapping would render a neutral stripe, silently losing
    # the signal the column exists for.
    %w[emerg alert crit err warning notice info debug].each do |level|
      assert LogsFieldCatalog.severity_color(level), "#{level} must map to a colour"
    end
  end

  test "the critical levels are coloured dark and err is not" do
    # crit/alert/emerg all render dark; err keeps danger. The distinction is what makes the
    # crit GROUP worth having -- if they shared a colour the grouping would be invisible.
    %w[emerg alert crit].each do |level|
      assert_equal "dark", LogsFieldCatalog.severity_color(level)
    end
    assert_equal "danger", LogsFieldCatalog.severity_color("err")
  end

  test "every filter term expands to at least one raw level" do
    # A term that covers nothing would produce a filter matching no record, which reads as
    # "no errors" rather than "you asked a bad question".
    LogsFieldCatalog::SEVERITY_FILTERS.each do |term, levels|
      assert levels.any?, "#{term} must cover at least one level"
      levels.each do |level|
        assert LogsFieldCatalog.severity_color(level),
               "#{term} covers #{level}, which must be a displayable level"
      end
    end
  end

  test "every filterable level is one the data can produce" do
    # The terms may group levels, but they may not invent them: each member has to be a name
    # `to_syslog_level` emits, or the filter would never match.
    emitted = %w[emerg alert crit err warning notice info debug]
    LogsFieldCatalog::SEVERITY_FILTERS.each_value do |levels|
      levels.each do |level|
        assert_includes emitted, level, "#{level} is not a syslog level name"
      end
    end
  end

  test "severity colours use bootstrap colour names" do
    valid = %w[primary secondary success danger warning info light dark]
    LogsFieldCatalog::SEVERITY_COLORS.each_value do |colour|
      assert_includes valid, colour
    end
  end

  test "the noisiest levels are the loudest colours" do
    assert_equal "danger", LogsFieldCatalog.severity_color("err")
    assert_equal "warning", LogsFieldCatalog.severity_color("warning")
    assert_equal "secondary", LogsFieldCatalog.severity_color("debug")
  end

  test "an unknown or absent level has no colour" do
    # The view turns nil into a neutral stripe. It must not guess a severity.
    assert_nil LogsFieldCatalog.severity_color(nil)
    assert_nil LogsFieldCatalog.severity_color("")
    assert_nil LogsFieldCatalog.severity_color("chatty")
  end

  test "severity lookup is case and whitespace insensitive" do
    assert_equal "danger", LogsFieldCatalog.severity_color("ERR")
    assert_equal "danger", LogsFieldCatalog.severity_color("  err  ")
    assert_equal "danger", LogsFieldCatalog.severity_color(:err)
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
