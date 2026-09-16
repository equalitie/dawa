#
# Builds LogsQL expressions from structured, already-split filter parts.
#
# LogsQL is a whitespace-separated AND of filters, so "a AND b" is just `a b`. We keep
# every fragment construction here (rather than in the controller/view/JS) so quoting
# and escaping are handled in exactly one place.
#
# Parts are emitted in a fixed order — field filters, then the free-text term, then the
# time range — so the resulting string is deterministic and assertable.
#
class VictoriaLogs
  module Query
    #
    # @param field_filters [Array<String>] raw LogsQL field filters, e.g. ["level:error"].
    # @param text [String, nil] free text, quoted as a phrase and ANDed.
    # @param time_range [String, nil] a `_time:` filter value, e.g. "1h" or "2026-01-01T00:00:00Z".
    # @param cursor [Time, nil] only logs strictly newer than this instant (live polling).
    # @return [String] the composed LogsQL expression (empty string means "everything").
    #
    # `time_range` and `cursor` are alternatives: a poll narrows to `_time:(cursor, now]`
    # rather than re-scanning the whole window. The cursor wins when both are supplied,
    # since it is the more specific bound and the intersection would only cost more.
    #
    def self.build(field_filters: [], text: nil, time_range: nil, cursor: nil)
      parts = []
      parts.concat(Array(field_filters).reject { |f| f.to_s.strip.empty? }.map(&:to_s))
      parts << quote(text) if text.to_s.strip.present?
      parts << (cursor ? cursor_filter(cursor) : range_filter(time_range))
      parts.compact.join(" ")
    end

    # An explicit `_time:` duration or instant, e.g. `_time:1h`.
    def self.range_filter(time_range)
      return nil if time_range.to_s.strip.empty?

      "_time:#{time_range}"
    end

    #
    # A half-open interval from `cursor` to now: `_time:(cursor, now]`.
    #
    # Half-open on the LEFT because the browser already holds the row at exactly `cursor`
    # (it came from the previous batch's newest record), so including it would re-show that
    # row on every poll. Closed on the right because the server evaluates `now` and a row
    # timestamped exactly at the boundary is one we have never sent. The client still
    # dedupes by key, because a cursor cannot distinguish rows sharing one timestamp.
    #
    # Rendered in UTC with microsecond precision to match VictoriaLogs' own `_time`
    # form, and quoted so a value containing punctuation cannot break the expression.
    #
    def self.cursor_filter(cursor)
      moment = cursor.utc.iso8601(6)
      "_time:(#{moment}, now]"
    end

    # Quote a free-text term as a LogsQL phrase, escaping embedded backslashes and
    # double quotes.
    def self.quote(term)
      escaped = term.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
      %("#{escaped}")
    end
  end
end
