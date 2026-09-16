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
    # @return [String] the composed LogsQL expression (empty string means "everything").
    #
    def self.build(field_filters: [], text: nil, time_range: nil)
      parts = []
      parts.concat(Array(field_filters).reject { |f| f.to_s.strip.empty? }.map(&:to_s))
      parts << quote(text) if text.to_s.strip.present?
      parts << "_time:#{time_range}" if time_range.to_s.strip.present?
      parts.join(" ")
    end

    # Quote a free-text term as a LogsQL phrase, escaping embedded backslashes and
    # double quotes.
    def self.quote(term)
      escaped = term.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
      %("#{escaped}")
    end
  end
end
