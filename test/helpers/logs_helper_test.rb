require "test_helper"

#
# Unit tests for the logs presenter. A record goes in, ordered display cells come out
# with the known LogsFieldCatalog columns first (in catalog order).
#
class LogsHelperTest < ActionView::TestCase
  def record
    {
      "host" => "tern",
      "programname" => "sshd",
      "unit" => "ssh.service",
      "severity" => "info",
      "priority" => "6",
      "_msg" => "Accepted publickey for admin",
      "_time" => "2026-09-11T18:29:29.700785038Z",
      "_stream" => "{host=\"tern\",programname=\"sshd\",unit=\"ssh.service\"}"
    }
  end

  test "log_display_cells returns known HOST_FIELDS first, in catalog order" do
    cells = log_display_cells(record)
    known = cells.select { |c| c[:known] }.map { |c| c[:field] }
    assert_equal LogsFieldCatalog::HOST_FIELDS, known
  end

  test "log_display_cells appends the remaining fields, sorted, as unknown" do
    cells = log_display_cells(record)
    others = cells.reject { |c| c[:known] }.map { |c| c[:field] }
    assert_equal [ :_stream ], others
    assert_equal "{host=\"tern\",programname=\"sshd\",unit=\"ssh.service\"}",
                 cells.find { |c| c[:field] == :_stream }[:value]
  end

  test "log_time formats the timestamp in the app zone" do
    with_time_zone("UTC") do
      assert_equal "Sep 11 18:29:29", log_time(record)
    end
  end

  test "log_time falls back to a dash for a blank time" do
    assert_equal "—", log_time({})
  end

  test "log_source prefers programname, then unit, then host, then stream" do
    assert_equal "sshd", log_source(record)
    assert_equal "ssh.service", log_source(record.except("programname"))
    assert_equal "tern", log_source(record.except("programname", "unit"))
    assert_equal "{host=\"x\"}", log_source({ "_stream" => "{host=\"x\"}" })
    assert_equal "—", log_source({})
  end

  test "log_message truncates long bodies" do
    assert_equal "short", log_message({ "_msg" => "short" })
    long = "x" * 500
    assert_operator log_message({ "_msg" => long }).length, :<, 200
  end

  test "log_json pretty-prints the whole record" do
    json = log_json({ "_msg" => "hi" })
    assert_includes json, "\"_msg\""
    assert_includes json, "\"hi\""
  end

  private

  def with_time_zone(zone)
    prior = Time.zone
    Time.zone = zone
    yield
  ensure
    Time.zone = prior
  end
end
