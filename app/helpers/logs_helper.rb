module LogsHelper
  #
  # Default range and the selectable windows now live in the field catalog / filters, so the
  # picker, the query builder, and the refresh endpoint cannot disagree about which windows
  # are legal.
  #
  RANGE_OPTIONS = LogsFilters::RANGE_OPTIONS
  DEFAULT_RANGE = LogsFilters::DEFAULT_RANGE

  # The selected time window (a `_time:` duration), constrained to RANGE_OPTIONS.
  def logs_range
    current_filters.range
  end

  # The selectable range options (exposed for the view without referencing the module
  # constant directly).
  def logs_range_options
    RANGE_OPTIONS
  end

  #
  # The current filter state for this request. Memoized per request so the page and any
  # partial share one parse, and so an invalid param is dropped exactly once.
  #
  def current_filters
    @current_filters ||= LogsFilters.new(params)
  end

  # The fields the user may filter on, as the catalog defines them.
  def logs_filterable_fields
    LogsFieldCatalog::HOST_FILTERABLE
  end

  #
  # A URL path carrying the given filter state as an explicit query string.
  #
  # Why not just `logs_path(**filter_params)`?
  #
  # A SYMBOL key named `host` is not a query param to a route helper: it is the URL
  # option that sets the request host, so it is consumed and never emitted.
  #
  #   logs_path(host: "tern")             # => "/logs"                (host consumed)
  #   logs_path({ "host" => "tern" })     # => "/logs?host=tern"      (string key: a param)
  #   logs_path(host: "tern", text: "x")  # => "/logs?text=x"         (host silently gone)
  #
  # `overrides` is a plain Hash (positional, not keywords) because callers pass `range`,
  # which would otherwise be captured as a keyword.
  #
  def logs_path_with(overrides = {}, filters: current_filters)
    query = filters.to_params(overrides).to_query
    query.present? ? "#{logs_path}?#{query}" : logs_path
  end

  #
  # The URL for the JSON refresh endpoint carrying the current filter state, so the
  # Stimulus controller starts from exactly what the server rendered.
  #
  def logs_refresh_path(filters = current_filters)
    query = filters.to_params.to_query
    query.present? ? "#{data_logs_path}?#{query}" : data_logs_path
  end

  #
  # The timestamp of a record, formatted in the app's zone. VictoriaLogs returns
  # `_time` as an RFC3339 string.
  #
  def log_time(record)
    value = record["_time"]
    return "—" if value.blank?

    Time.zone.parse(value).strftime("%b %d %H:%M:%S")
  rescue ArgumentError, TypeError
    value.to_s
  end

  #
  # A human "source" label for a host log. Host records are normalized by the
  # `parse_host_logs` transform, so prefer `programname` (the daemon), then `host` (the
  # machine). `unit` is not used: it is not a display column, and falling back to it made
  # the label inconsistent with the Program column it sat next to.
  #
  def log_source(record)
    record["programname"].presence ||
      record["host"].presence ||
      record["_stream"].presence ||
      "—"
  end

  # A short, single-line preview of the message body.
  def log_message(record, length: 160)
    record["_msg"].to_s.truncate(length)
  end

  #
  # Normalize a record into ordered display cells: the known HOST_FIELDS first (in that
  # exact order), then any "other" fields the record carries (sorted). This is the one
  # place that decides field order; the table and (later) facets read from it.
  #
  # @return [Array<Hash>] e.g. [{ field: :_time, value: "...", known: true }, ...]
  #
  def log_display_cells(record)
    known = LogsFieldCatalog::HOST_FIELDS
    known_cells = known.map do |field|
      { field: field, value: log_field_value(record, field), known: true }
    end
    others = (record.keys.map(&:to_sym) - known).sort.map do |field|
      { field: field, value: log_field_value(record, field), known: false }
    end
    known_cells + others
  end

  # The display value for a single field of a record (used by the "other" columns).
  def log_field_value(record, field)
    record[field.to_s]
  end

  # The full record rendered as pretty JSON, for copy/paste out of the UI.
  def log_json(record)
    JSON.pretty_generate(record)
  end

  #
  # The record as ordered key/value pairs for the message cell's disclosure body.
  #
  # Pairs rather than a JSON string because the body is rendered as a list of
  # "key: value" rows, and the client has to rebuild the same markup. Values are stringified
  # here so both sides treat a number, a bool, and a string the same way.
  #
  # `_msg` is EXCLUDED: it carries the payload the row exists to show, so it is rendered on
  # its own above the list (see `log_row_cell`) rather than as one labelled entry among
  # metadata. Everything else keeps the record's own order.
  #
  def log_record_pairs(record)
    record.except("_msg").map { |key, value| { key: key.to_s, value: stringify(value) } }
  end

  # A record value as display text. Non-strings are stringified so a number, a bool, and a
  # string all render the same way.
  def stringify(value)
    value.is_a?(String) ? value : value.to_s
  end

  ##
  ## JSON refresh (Step 4)
  ##

  #
  # One record as the JSON row the refresh endpoint returns.
  #
  # The row carries `cells`: one entry per visible column, in `LogsFieldCatalog` order,
  # already formatted. The client renders whatever it is given rather than knowing the
  # column list, so there is exactly one place that decides which columns exist and how
  # they look. That is what keeps a live-appended row identical to a server-rendered one --
  # an earlier version hardcoded a few columns in JS and silently dropped the rest.
  #
  def log_row(record)
    {
      key: log_row_key(record),
      time: record["_time"],
      classes: log_row_cell_classes(record),
      cells: log_row_cells(record)
    }
  end

  #
  # The message cell, as a disclosure: the truncated message is the summary and the full
  # record's JSON is the body, so the row stays one line high until the user asks for more.
  # The JSON used to be its own column, which cost a column of width on every row to show a
  # control most rows never used.
  #
  def log_row_cells(record)
    LogsFieldCatalog::HOST_FIELDS.map { |field| log_row_cell(record, field) }
  end

  # One column's markup description. Mirrors `logs/_cell.html.haml` exactly.
  def log_row_cell(record, field)
    # Severity is handled before the blank check: an absent level is still a rendered
    # stripe (neutral), because the column's width carries meaning even when the value
    # does not. A blank cell would collapse the stripe and shift the row.
    return { kind: :severity, color: LogsFieldCatalog.severity_color(record["severity"]),
             value: record["severity"].to_s } if field == :severity

    value = log_field_value(record, field)
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
        table.column :shrink, class: "log-severity-cell"
      elsif field == :_msg
        table.column :grow, label: t("logs.field.#{field}")
      else
        table.column :shrink, label: t("logs.field.#{field}")
      end
    end
  end

  #
  # The <td> classes for one log row's cells, composed exactly as `v.table_row` composes
  # them.
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
      extra = cells[index][:kind] == :severity ? LogsFieldCatalog.severity_class(cells[index][:color]) : nil
      row.cell_class_list(TableCellComponent.new(class: extra), index).join(" ")
    end
  end

  #
  # A stable identity for a record, used to drop rows we have already shown.
  #
  # Timestamps are NOT unique: syslog can emit several lines within the same microsecond,
  # and journald records are frequently emitted in bursts sharing a `_time`. Keying on time
  # alone would therefore discard real logs. `_stream_id` + `_time` + the message body is
  # specific enough in practice, and stays stable across polls because every part comes from
  # the record itself.
  #
  def log_row_key(record)
    stream = record["_stream_id"].presence || record["_stream"].presence || record["host"].presence || ""
    "#{stream}|#{record["_time"]}|#{record["_msg"]}"
  end
end
