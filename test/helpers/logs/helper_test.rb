require "test_helper"

#
# Unit tests for the logs filter/page helpers and the log table helpers.
#
# Both modules are included here rather than split, because the table helper stands on the
# page helper (`log_row_cell` calls `log_context` / `log_source`) and the interesting cases
# cross the boundary.
#
class Logs::DisplayHelperTest < ActionView::TestCase
  include Logs::DisplayHelper
  include Logs::TableHelper

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

  test "log_time formats the timestamp in the app zone" do
    with_time_zone("UTC") do
      assert_equal "Sep 11 18:29:29", log_time(record)
    end
  end

  test "log_time falls back to a dash for a blank time" do
    assert_equal "—", log_time({})
  end

  test "log_context is 'host' for a host record and the installation for a container" do
    # The context is what KIND of thing logged this: the machine for a host log, the app
    # installation for a container. It is not a field on the record either way.
    assert_equal "host", log_context(record)
    assert_equal "host", log_context({})
    assert_equal "peertube-1", log_context({ "dc_app" => "peertube", "dc_inst" => "peertube-1" })
  end

  test "log_context falls back to dc_app when dc_inst is absent" do
    # A container labeled before `dc_inst` existed still needs a context, not an empty one.
    assert_equal "peertube", log_context({ "dc_app" => "peertube" })
  end

  test "log_source is the daemon for a host record" do
    assert_equal "sshd", log_source(record)
  end

  test "log_source falls back through the host chain" do
    # `programname` is the daemon; `unit` and `host` are progressively less specific but still
    # identify the row, and a weak label beats a blank one.
    assert_equal "ssh.service", log_source(record.except("programname"))
    assert_equal "tern", log_source(record.except("programname", "unit"))
    assert_nil log_source({})
  end

  test "log_source prefers dc_name, then container_name, then a short container id" do
    # Most human-readable first. `dc_name` is not emitted yet -- the composer sets
    # dc_app/dc_inst/dc_env/dc_version -- so today this resolves to `container_name` in
    # practice, and the id is the last resort.
    id = "a1b2c3d4e5f60718293a4b5c6d7e8f90"
    base = { "dc_app" => "peertube" }

    assert_equal "dawa-web-1", log_source(base.merge("container_name" => "dawa-web-1"))
    assert_equal "custom", log_source(base.merge("dc_name" => "custom", "container_name" => "dawa-web-1")),
                 "dc_name wins once it exists"
    assert_equal "a1b2c3d4e5f6", log_source(base.merge("container_id" => id)),
                 "the id is shortened to docker's 12-character convention"
    assert_nil log_source(base), "an unnamed container has no source"
  end

  test "a container record is one with a Dawa app label" do
    # The single test the two columns have to agree on: one column showing a container context
    # beside a host source would be nonsense.
    assert container_record?({ "dc_app" => "peertube" })
    assert container_record?({ "dc_inst" => "peertube-1" })
    refute container_record?(record)
    refute container_record?({ "container_name" => "dawa-web-1" }),
           "a container name alone does not make it a Dawa-managed app"
  end

  test "the context and source columns each carry one part" do
    # Neither is a field lookup, and a container row has no `programname` at all, so a plain
    # lookup would render the empty-column placeholder on every one of them.
    assert_equal :context, log_row_cell(record, :context)[:kind]
    assert_equal "host", log_row_cell(record, :context)[:value]
    assert_equal :source, log_row_cell(record, :programname)[:kind]
    assert_equal "sshd", log_row_cell(record, :programname)[:value]

    container = { "dc_app" => "peertube", "container_name" => "dawa-web-1" }
    assert_equal "peertube", log_row_cell(container, :context)[:value]
    assert_equal "dawa-web-1", log_row_cell(container, :programname)[:value]
  end

  test "a container row with no container labels still renders both columns" do
    # The label chain can bottom out; the cell must not fall back to the empty placeholder,
    # because the column is a derivation rather than a field and "no name" is not "no value".
    container = { "dc_app" => "mastodon" }

    assert_equal :context, log_row_cell(container, :context)[:kind]
    assert_equal "mastodon", log_row_cell(container, :context)[:value]
    assert_equal :source, log_row_cell(container, :programname)[:kind]
    assert_nil log_row_cell(container, :programname)[:value]
  end

  test "short_container_id truncates to docker's convention and tolerates blanks" do
    assert_equal "a1b2c3d4e5f6", short_container_id("a1b2c3d4e5f60718293a4b5c6d7e8f90")
    assert_equal "abc", short_container_id("abc")
    assert_nil short_container_id(nil)
    assert_nil short_container_id("")
  end

  test "source_label_color is a pure function of the text" do
    # The whole point: a reader learns "peertube is the blue one", so the same string must
    # give the same colour on every request. Anything random or counter-based would break it.
    assert_equal source_label_color("sshd"), source_label_color("sshd")
    assert_equal source_label_color("peertube"), source_label_color("peertube")
  end

  test "source_label_color stays inside the hue range" do
    # Clamped away from the wrap point at 0/360, where two unrelated names would look alike.
    names = %w[sshd cron systemd kernel nginx a b zzz postgres mastodon]

    names.each do |name|
      hue = source_label_color(name)[/hsl\((\d+)/, 1].to_i
      assert_operator hue, :>=, Logs::DisplayHelper::SOURCE_HUE_MIN, "#{name} below the floor"
      assert_operator hue, :<, Logs::DisplayHelper::SOURCE_HUE_MIN + Logs::DisplayHelper::SOURCE_HUE_SPAN,
                      "#{name} above the ceiling"
    end
  end

  test "source_label_color uses fixed saturation and lightness" do
    # Only the hue varies. Varying brightness would read as meaning that is not there and
    # would make some labels harder to read than others.
    assert_equal "hsl(187 80% 80%)", source_label_color("sshd")
    assert_match(/hsl\(\d+ #{Logs::DisplayHelper::SOURCE_BADGE_SATURATION}% #{Logs::DisplayHelper::SOURCE_BADGE_LIGHTNESS}%\)/,
                 source_label_color("anything"))
  end

  test "source_label_color separates labels that share a plain sum" do
    # Regression: with an unweighted sum, `sshd` and `cron` hashed identically (both 434),
    # because a sum cannot see character order or position. Weighting by index fixes it.
    refute_equal source_label_color("sshd"), source_label_color("cron")
    refute_equal weighted_ordinal_sum("sshd"), weighted_ordinal_sum("cron")
    # Anagrams are the same failure mode.
    refute_equal source_label_color("evil"), source_label_color("live")
  end

  test "a blank label has no colour" do
    # A hash of "" would produce a valid-looking colour for a badge with nothing in it, so
    # the caller can fall back to a neutral badge instead.
    assert_nil source_label_color(nil)
    assert_nil source_label_color("")
  end

  test "the source cell carries the label's colour" do
    cell = log_row_cell(record, :programname)

    assert_equal "sshd", cell[:value]
    assert_equal source_label_color("sshd"), cell[:color]
  end

  test "the source cell has no colour when there is no label" do
    cell = log_row_cell({ "dc_app" => "mastodon" }, :programname)

    assert_nil cell[:value]
    assert_nil cell[:color], "an unnamed container must not get a confident-looking badge"
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
