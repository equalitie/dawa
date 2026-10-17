#
# The log table: columns, cells, and the markup for each kind of cell.
#
# This is the one place that decides what a log row looks like. The HTML view and the JSON
# refresh endpoint both go through it -- `log_row_cells` produces the cell descriptors, and
# `log_cell_markup` renders one -- so a row appended live by the Stimulus controller is built
# from exactly the same rules as a row the server rendered. An earlier version had the
# formatting written out twice, in `_cell.html.haml` and again in JS, and the two drifted.
#
# The JS half is `cellHtml` in `logs_explorer_controller.js`. The two are a pair: a `kind`
# added here needs a matching case there, or live rows will show the fallback.
#
module Logs::TableHelper
  # The <td> class that carries the severity stripe. Named rather than inlined because the
  # stylesheet, the column declaration, and the cell classes all have to agree on it.
  SEVERITY_CELL_CLASS = "log-severity-cell".freeze

  ##
  ## columns
  ##

  #
  # The log table's columns definition
  #
  def logs_table_columns
    Logs::FieldCatalog::HOST_FIELDS.map do |field|
      if Logs::FieldCatalog.unlabelled?(field)
        [ :shrink, { class: SEVERITY_CELL_CLASS } ]
      elsif field == :_msg
        [ :grow, t("logs.field.#{field}") ]
      else
        [ :shrink, t("logs.field.#{field}") ]
      end
    end
  end

  #
  # The <td> classes for one log row's cells, composed exactly as `v.table_row` composes them.
  #
  # The refresh endpoint publishes these with each row so the Stimulus controller can build
  # the same element the row template builds. Deriving them from the column list rather than
  # restating them in JS is the whole point: the two were written out independently once and
  # drifted, and the log table's severity column stopped matching between loaded and appended
  # rows.
  #
  # @return [Array<String>] one class string per cell, in cell order.
  #
  def log_row_cell_classes(record, hover: true)
    row = TableRowComponent.new(hover: hover, columns: logs_table_columns)
    cells = log_row_cells(record)
    cells.each_index.map do |index|
      extra = Logs::FieldCatalog.severity_class(cells[index][:color]) if cells[index][:kind] == :severity
      row.cell_class_list(TableCellComponent.new(class: extra), index).join(" ")
    end
  end

  ##
  ## cell descriptors
  ##

  #
  # The cells for one record: one descriptor per catalog column, in catalog order.
  #
  # Each descriptor is tagged with the kind of markup it needs, so a caller can render it
  # without knowing the formatting rules (truncation, badge classes, the "none" placeholder).
  # Text that needs translating -- the empty-cell placeholder -- arrives ready to render, so
  # the JS never holds a string.
  #
  # @return [Array<Hash>] e.g. [{ kind: :time, value: "Sep 08 00:59:12" }, ...]
  #
  def log_row_cells(record)
    Logs::FieldCatalog::HOST_FIELDS.map { |field| log_row_cell(record, field) }
  end

  # One column's descriptor. Mirrors the `when` branches in `log_cell_markup` exactly.
  def log_row_cell(record, field)
    if field == :severity
      return { kind: :severity, color: Logs::FieldCatalog.severity_color(record["severity"]),
               value: record["severity"].to_s }
    end

    return { kind: :context, value: log_context(record) } if field == :context
    if field == :programname
      source = log_source(record)
      return { kind: :source, value: source, color: source_label_color(source) }
    end

    value = record[field.to_s]
    # The placeholder is translated here rather than in JS so the client holds no strings.
    return { kind: :none, value: t("logs.index.none") } if value.blank?

    case field
    when :_time
      { kind: :time, value: log_time(record) }
    when :_msg
      { kind: :message, value: log_message(record), message: stringify(record["_msg"]),
        fields: log_record_pairs(record) }
    else
      { kind: :badge, value: value }
    end
  end

  ##
  ## cell markup
  ##

  #
  # One cell's markup, driven by a descriptor from `log_row_cell`.
  #
  def log_cell_markup(cell)
    case cell[:kind]
    when :severity
      tag.span("", class: "d-none", title: cell[:value].presence || t("logs.index.none"),
                    data: { bs_toggle: "tooltip" })
    when :time
      tag.span(cell[:value], class: "text-nowrap")
    when :message
      log_message_cell(cell)
    when :context
      tag.span(cell[:value], class: "badge text-bg-light")
    when :source
      log_badge(cell)
    when :badge
      log_badge(cell)
    else
      tag.span(cell[:value], class: "text-muted")
    end
  end

  def log_badge(cell)
    return tag.span(cell[:value], class: "badge text-bg-light") if cell[:color].blank?

    tag.span(cell[:value], class: "badge text-dark", style: "background-color: #{cell[:color]}")
  end

  def log_message_cell(cell)
    fields = cell[:fields].map do |field|
      tag.li(tag.i(field[:key]) + ": #{field[:value]}".html_safe)
    end

    tag.details(
      tag.summary(tag.span(cell[:value], class: "log-message-summary-text"), class: "text-truncate") +
        tag.div(cell[:message], class: "mb-3", data: { action: "click->logs-explorer#collapseMessage" }) +
        tag.ul(safe_join(fields), class: "list-unstyled small mb-0", data: { action: "click->logs-explorer#collapseMessage" }),
      class: "log-message"
    )
  end
end
