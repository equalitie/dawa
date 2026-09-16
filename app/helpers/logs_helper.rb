module LogsHelper
  # Selectable "last N" windows for the time filter, shortest first. The values are
  # LogsQL `_time:` durations; the labels are translated.
  RANGE_OPTIONS = %w[15m 1h 6h 24h 7d].freeze
  DEFAULT_RANGE = "1h"

  # The selected time window (a `_time:` duration), constrained to RANGE_OPTIONS.
  def logs_range
    value = params[:range].to_s
    RANGE_OPTIONS.include?(value) ? value : DEFAULT_RANGE
  end

  # The selectable range options (exposed for the view without referencing the module
  # constant directly).
  def logs_range_options
    RANGE_OPTIONS
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
end
