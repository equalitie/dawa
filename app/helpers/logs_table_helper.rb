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
module LogsTableHelper
  # The <td> class that carries the severity stripe. Named rather than inlined because the
  # stylesheet, the column declaration, and the cell classes all have to agree on it.
  SEVERITY_CELL_CLASS = "log-severity-cell".freeze

  ##
  ## columns
  ##

  #
  # Declares the log table's columns on a `v.table` builder.
  #
  # The view and `log_row_cell_classes` both call this, so the header and the row classes are
  # generated from one column list. Declaring columns twice is exactly how the severity
  # stripe's width class ended up on the server-rendered cells but not the appended ones.
  #
  # The message column grows and is last: it holds the row's only elastic content, since the
  # full record's JSON now lives inside it as a disclosure rather than in a column of its own.
  #
  def logs_table_columns(table)
    LogsFieldCatalog::HOST_FIELDS.each do |field|
      if LogsFieldCatalog.unlabelled?(field)
        table.column :shrink, class: SEVERITY_CELL_CLASS
      elsif field == :_msg
        table.column :grow, label: t("logs.field.#{field}")
      else
        table.column :shrink, label: t("logs.field.#{field}")
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
  # The row component is instantiated directly rather than through `v.table_row`, which
  # renders eagerly and would return HTML instead of the builder whose class list we want.
  #
  # @return [Array<String>] one class string per cell, in cell order.
  #
  def log_row_cell_classes(record, hover: true)
    row = TableRowComponent.new(hover: hover)
    logs_table_columns(row)
    cells = log_row_cells(record)
    cells.each_index.map do |index|
      extra = LogsFieldCatalog.severity_class(cells[index][:color]) if cells[index][:kind] == :severity
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
    LogsFieldCatalog::HOST_FIELDS.map { |field| log_row_cell(record, field) }
  end

  # One column's descriptor. Mirrors the `when` branches in `log_cell_markup` exactly.
  def log_row_cell(record, field)
    # Severity is handled before the blank check: an absent level is still a rendered stripe
    # (neutral), because the column's width carries meaning even when the value does not. A
    # blank cell would collapse the stripe and shift the row.
    if field == :severity
      return { kind: :severity, color: LogsFieldCatalog.severity_color(record["severity"]),
               value: record["severity"].to_s }
    end

    # The Context and Source columns are both resolved before the blank check. Neither is a
    # field lookup -- a container row has no `programname` at all, so a raw lookup would place
    # the empty-column placeholder on every such row.
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
      # The summary is the readable preview, and the body repeats the message in full above
      # the metadata list: the preview is Ruby-truncated and CSS-ellipsised, so the disclosure
      # is where the whole line becomes readable.
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
  # A helper rather than a partial because the descriptor already carries everything the
  # markup needs, so there is no template-local state to keep in a locals hash, and because
  # the whole kind switch reads better as one piece of Ruby than as a chain of `when` blocks
  # in a template.
  #
  # Replaces `logs/_cell.html.haml`, which this method is a direct translation of.
  #
  def log_cell_markup(cell)
    case cell[:kind]
    when :severity
      # Nothing but the value: the colour and width live on the <td> itself (see
      # `log-severity-cell` in _dawa.scss), so there is no inner element to inset it or add
      # padding. The level is not visible text, so it rides in the title for discoverability
      # and remains in the message cell's field list.
      #
      # An empty span is emitted deliberately: Haml needed *something* here and `cellHtml` in
      # the JS builds the same shape. The <td> already carries the colour class.
      tag.span("", class: "d-none", title: cell[:value].presence || t("logs.index.none"),
                    data: { bs_toggle: "tooltip" })
    when :time
      tag.span(cell[:value], class: "text-nowrap")
    when :message
      log_message_cell(cell)
    when :context
      # The Context column: what KIND of thing logged this ("host", or the app installation
      # for a container). Light rather than filled because it is the low-variance half -- on a
      # single-host install it is the same word on most rows -- so it should not compete with
      # the identifier beside it.
      tag.span(cell[:value], class: "badge text-bg-light")
    when :source
      # The Source column: which specific thing within that context (the daemon, or the
      # container). Where the context is fixed, this varies per program, so it also carries a
      # per-string colour. Otherwise it is a "badge".
      log_badge(cell)
    when :badge
      log_badge(cell)
    else
      # `:none` (and any kind this helper does not know) renders a muted placeholder, so a
      # cell kind added to `log_row_cell` without markup here degrades visibly rather than
      # breaking the row.
      tag.span(cell[:value], class: "text-muted")
    end
  end

  # A badge filled with the colour derived from its own text, or a neutral one when there is
  # no text to derive a colour from.
  #
  # The per-string colour (`source_label_color`) is what lets the eye follow one daemon or
  # container through a page of mixed logs: the same label is always the same colour, in this
  # request and every later one. The text stays dark rather than white because the generated
  # colours are light (80% lightness); `text-dark` is what reads against them. A label with no
  # text (a container we could not name) gets no colour at all, so an empty badge is not drawn
  # as a confident one.
  #
  def log_badge(cell)
    return tag.span(cell[:value], class: "badge text-bg-light") if cell[:color].blank?

    tag.span(cell[:value], class: "badge text-dark", style: "background-color: #{cell[:color]}")
  end

  #
  # The message disclosure: the one-line preview as the summary, the whole record as the body.
  #
  # `<details>` gives click-to-expand with no JS and no state to keep in step, so a
  # live-appended row behaves like a loaded one.
  #
  # The body leads with `_msg` on its own, unlabelled and at the table's normal font size: it
  # is the line the row exists to show, not one field among many, so it reads as the message
  # continued rather than as a labelled entry. The remaining fields follow as a list of
  # "key: value" rows, which is quicker to scan than braces and quotes.
  #
  # The summary text is wrapped in a span so the stylesheet can hide JUST the text while the
  # disclosure is open (the body repeats it in full, so showing both prints the line twice).
  #
  # Collapsing is driven by clicking the body, not the summary: once the summary text is hidden
  # the summary is an empty strip, which is an invisible and undiscoverable hit target. The
  # summary stays as the control for keyboard and assistive tech, which is what `<details>`
  # provides natively.
  #
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
