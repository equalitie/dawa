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

  def test_table_rows_do_not_inherit_a_stale_key
    # Guards the exact shape the log explorer relies on for client-side dedupe.
    first = v.table_row(data: { "row-key": "one" }) { |r| r.with_cell { "a" } }
    second = v.table_row(data: { "row-key": "two" }) { |r| r.with_cell { "b" } }

    assert_includes first, 'data-row-key="one"'
    assert_includes second, 'data-row-key="two"'
    refute_includes second, "one"
  end
end
