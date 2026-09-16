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
  # `parse_host_logs` transform, so prefer `programname` (the daemon), then `unit`
  # (the systemd unit), then `host` (the machine).
  #
  def log_source(record)
    record["programname"].presence ||
      record["unit"].presence ||
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

  # The full record rendered as pretty JSON, for the collapsible "full JSON" cell.
  def log_json(record)
    JSON.pretty_generate(record)
  end

  ##
  ## JSON refresh (Step 4)
  ##

  #
  # One record as the JSON row the refresh endpoint returns.
  #
  # The client renders rows from this shape rather than re-deriving display strings, so the
  # live-appended rows are formatted by the same Ruby that formatted the initial page render.
  # That is what keeps "live" from looking subtly different from "loaded": time formatting,
  # truncation, and the source badge all stay server-side.
  #
  # `key` is the identity used for client-side dedupe when batches overlap at a cursor
  # boundary. See `log_row_key`.
  #
  def log_row(record)
    {
      key: log_row_key(record),
      time: record["_time"],
      time_display: log_time(record),
      source: log_source(record),
      message: log_message(record),
      message_full: record["_msg"].to_s,
      json: log_json(record)
    }
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
