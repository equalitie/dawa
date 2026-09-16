require "faraday"
require "json"

#
# Thin wrapper around VictoriaLogs' LogsQL HTTP API.
#
# Unlike VictoriaMetrics VictoriaLogs exposes a
# LogsQL query API whose `/select/logsql/query` endpoint returns **newline-delimited
# JSON (NDJSON)** — one JSON object per line rather than a JSON array. This service
# hides that transport detail and returns arrays of parsed records, so callers (the
# logs controller/explorer) never touch raw HTTP or NDJSON.
#
# Logs are flat objects whose system fields include `_time`, `_stream`, `_stream_id`
# and `_msg`; everything else is whatever the emitter sent (`level`, `programname`,
# container labels, ...).
#
# Example:
#   VictoriaLogs.new.query_lines("error", limit: 100)
#   # => [ { "_time" => "2026-09-08T00:59:12Z", "_msg" => "boom" }, ... ]
#
class VictoriaLogs
  # Raised when VictoriaLogs answers with a non-2xx status or a body we can't parse.
  # Connection/timeout failures surface as their underlying Faraday error so callers
  # can distinguish "unreachable" from "reached but failed".
  class RequestError < StandardError; end

  # Default cap applied server-side before asking VictoriaLogs for log records.
  DEFAULT_LIMIT = 200

  def initialize(url: nil, open_timeout: 2, timeout: 10)
    @url = url || Conf.logs_url
    @open_timeout = open_timeout
    @timeout = timeout
  end

  # The endpointless base URL this service talks to (useful for diagnostics).
  attr_reader :url

  #
  # Run a LogsQL query and return the matching logs as parsed Hashes.
  #
  # @param query [String] a LogsQL expression ("" means "everything").
  # @param limit [Integer, nil] the most recent N matching logs (server-clamped by callers).
  # @param offset [Integer, nil] skip the most recent N matches (simple pagination).
  # @return [Array<Hash>] parsed log records (empty when nothing matches).
  #
  def query_lines(query = "", limit: nil, offset: nil)
    params = { query: query.to_s }
    params[:limit] = limit if limit
    params[:offset] = offset if offset

    body = get("/select/logsql/query", params)
    parse_ndjson(body)
  end

  #
  # Known stream field-value combinations, used to populate the "source/provider" picker.
  #
  # @param query [String, nil] optional LogsQL filter to scope the streams.
  # @return [Array<Hash>] one parsed object per stream.
  #
  def streams(query = nil)
    params = {}
    params[:query] = query if query.present?
    parse_ndjson(get("/select/logsql/streams", params))
  end

  #
  # The field names present in the logs (optionally scoped by a query/range). Used to
  # reconcile the shared LogsFieldCatalog against what the deployment actually emits.
  #
  # @return [Array<String>] field names, e.g. ["_msg", "_stream", "_time", "programname"].
  #
  def field_names(query = nil)
    params = {}
    params[:query] = query if query.present?
    parse_values(get("/select/logsql/field_names", params))
  end

  #
  # Build a LogsQL expression from structured filter parts, ANDing them together.
  #
  # Order is fixed (fields first, then the free-text term, then the time range) so the
  # output is deterministic and easy to assert in tests. All quoting/escaping happens
  # here — callers never hand-assemble LogsQL.
  #
  #   VictoriaLogs::Query.build(field_filters: ["programname:sshd"], text: "failed login")
  #   # => 'programname:sshd "failed login"'
  #
  def self.build_query(field_filters: [], text: nil, time_range: nil)
    Query.build(field_filters: field_filters, text: text, time_range: time_range)
  end

  private

  def connection
    @connection ||= Faraday.new(url: @url) do |f|
      f.options.open_timeout = @open_timeout
      f.options.timeout = @timeout
      f.response :raise_error
    end
  end

  # GET a LogsQL endpoint and return the raw response body (String).
  def get(path, params)
    response = connection.get(path, params)
    response.body.to_s
  rescue Faraday::Error => e
    # Faraday's :raise_error middleware turns non-2xx into Faraday::ClientError/
    # ServerError; wrap those as our RequestError. Connection/timeout errors are
    # re-raised as-is so callers can tell "unreachable" apart from "bad response".
    raise RequestError, "VictoriaLogs request failed: #{e.message}" if e.response

    raise
  end

  # Parse an NDJSON body (one JSON object per line), skipping blank lines.
  def parse_ndjson(body)
    body.to_s.each_line.filter_map do |line|
      stripped = line.strip
      next if stripped.empty?

      begin
        JSON.parse(stripped)
      rescue JSON::ParserError => e
        raise RequestError, "malformed NDJSON from VictoriaLogs: #{e.message}"
      end
    end
  end

  # Parse the `{ "values": [ { "value": ..., "hits": N }, ... ] }` shape shared by
  # /field_names and /field_values, returning just the string values.
  def parse_values(body)
    stripped = body.to_s.strip
    return [] if stripped.empty?

    parsed = begin
      JSON.parse(stripped)
    rescue JSON::ParserError => e
      raise RequestError, "malformed JSON from VictoriaLogs: #{e.message}"
    end

    values = parsed.is_a?(Hash) ? parsed["values"] : parsed
    Array(values).filter_map do |entry|
      entry.is_a?(Hash) ? entry["value"]&.to_s : entry.to_s
    end
  end
end
