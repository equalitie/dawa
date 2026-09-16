require_relative "test_helper"

#
# Tests for the table components' common-argument handling.
#
# These exist because tables silently DROPED `data:`/`html:` until recently: the templates
# read only `@html[:class]`. That is invisible in most rendering tests (the table still
# looks right) but breaks anything that needs to hang a Stimulus target or an id off the
# table or one of its rows -- which the live log explorer does.
#
class TableComponentTest < ActionView::TestCase
  def test_table_applies_an_id_and_data_attributes
    html = v.table("Logs", id: "logs-table", data: { "logs-explorer-target": "rows" }) do |t|
      t.column :shrink, label: "Time"
    end

    assert_includes html, 'id="logs-table"'
    assert_includes html, 'data-logs-explorer-target="rows"'
  end

  def test_table_keeps_its_computed_classes_alongside_custom_ones
    # `class` is excluded from the attribute splat so it cannot override table_classes.
    html = v.table("Logs", class: "custom-class") do |t|
      t.column :shrink, label: "Time"
    end

    assert_includes html, "table table-headerless table-shrink table-hover align-middle"
    assert_includes html, "custom-class"
  end

  def test_table_row_applies_an_id_and_data_attributes
    html = v.table_row(id: "row-1", data: { "row-key": "abc123" }) do |r|
      r.with_cell { "cell" }
    end

    assert_includes html, 'id="row-1"'
    assert_includes html, 'data-row-key="abc123"'
  end

  ##
  ## structure (row insertion point)
  ##

  def test_table_wraps_rows_in_a_tbody
    # A real <tbody> gives script a valid insertion point. Browsers synthesize one anyway,
    # but that synthesized element is not addressable: `table.prepend(row)` puts a row
    # before the header and the parser hoists it out of the table, which is how live-inserted
    # log rows ended up rendering above the table.
    html = v.table("Logs") do |t|
      t.column :shrink, label: "Time"
      t.with_row do |r|
        r.with_cell { "row" }
      end
    end

    assert_includes html, "<tbody"
  end

  def test_table_labels_live_in_a_thead
    html = v.table("Logs") do |t|
      t.column :shrink, label: "Time"
    end

    assert_includes html, "<thead"
  end

  def test_a_column_can_carry_extra_header_classes
    # Used by the log explorer's severity stripe, which is a fixed-width column with no
    # label. Without this the width could only be set by special-casing the template.
    #
    # NOTE: the extra class needs a header row to exist at all -- `column_labels?` is false
    # when NO column is labelled, so the whole thead (and every th) is skipped. These tests
    # therefore include a labelled column, as the logs table does.
    html = v.table("Logs") do |t|
      t.column :shrink, class: "log-severity-cell"
      t.column :shrink, label: "Time"
    end

    assert_match(/<th[^>]*log-severity-cell/, html)
  end

  def test_a_labelled_column_still_accepts_extra_classes
    html = v.table("Logs") do |t|
      t.column :shrink, label: "Time", class: "custom-col"
    end

    assert_match(/<th[^>]*custom-col/, html)
    assert_includes html, "Time"
  end

  def test_body_data_lands_on_the_tbody_not_the_table
    # The refresh controller targets the row container, so it must be able to mark the
    # <tbody> specifically rather than the <table>.
    html = v.table("Logs", body_data: { "logs-explorer-target": "rows" }) do |t|
      t.column :shrink, label: "Time"
      t.with_row do |r|
        r.with_cell { "row" }
      end
    end

    assert_match(/<tbody[^>]*data-logs-explorer-target="rows"/, html)
    refute_match(/<table[^>]*data-logs-explorer-target/, html)
  end

  def test_table_data_still_lands_on_the_table
    html = v.table("Logs", data: { "table-target": "x" }) do |t|
      t.column :shrink, label: "Time"
    end

    assert_match(/<table[^>]*data-table-target="x"/, html)
  end

  def test_rows_render_inside_the_tbody
    html = v.table("Logs") do |t|
      t.column :shrink, label: "Time"
      t.with_row do |r|
        r.with_cell { "first" }
      end
    end

    tbody = html[/<tbody.*?<\/tbody>/m]
    assert_includes tbody, "first", "rows must sit inside the tbody"
  end

  def test_table_rows_do_not_inherit_a_stale_key
    # Guards the exact shape the log explorer relies on for client-side dedupe.
    first = v.table_row(data: { "row-key": "one" }) { |r| r.with_cell { "a" } }
    second = v.table_row(data: { "row-key": "two" }) { |r| r.with_cell { "b" } }

    assert_includes first, 'data-row-key="one"'
    assert_includes second, 'data-row-key="two"'
    refute_includes second, "one"
  end
end
