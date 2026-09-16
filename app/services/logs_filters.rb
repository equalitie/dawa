#
# The user's current log-explorer filter state, parsed from request params.
#
# Step 4's rule is that the browser owns filter *state* but never builds LogsQL. This
# object is the server half of that split: it takes the raw params hash (from a page load
# or from the JSON refresh endpoint), validates everything against allowlists, and hands
# the controller structured pieces it can pass to `VictoriaLogs.build_query`.
#
# Validation lives here rather than in the controller so the HTML page and the JSON
# endpoint cannot drift: both construct a Filters from params and therefore accept exactly
# the same inputs. Anything unrecognized is dropped rather than passed through, because
# this state is attacker-controllable via the query string.
#
# Deliberately does NOT build the query string. `VictoriaLogs::Query` owns quoting and
# ordering; this only decides *what* the user asked for.
#
class LogsFilters
  # `_time:` durations the picker offers, shortest first.
  RANGE_OPTIONS = %w[15m 1h 6h 24h 7d].freeze
  DEFAULT_RANGE = "1h"

  # A free-text term longer than this is almost certainly a mistake (or an attack), and it
  # only inflates the LogsQL we send.
  MAX_TEXT_LENGTH = 200

  # A low bound on the cursor to keep `_time:(cursor, now]` from being meaningful only to
  # second precision; see the cursor discussion in `cursor_boundary`.
  ISO8601_PATTERN = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})\z/

  attr_reader :range, :host, :programname, :severity, :text

  #
  # @param params [Hash] request params (`params.to_unsafe_h` or a plain hash from a
  #   parsed JSON body). Accepts symbol or string keys.
  #
  # A LogsFilters may be built from a controller's params (ActionController::Parameters, which
  # is not a Hash and refuses `to_h` unless permitted) or from a plain parsed-JSON Hash.
  # Only the known keys are read, so unknown/unpermitted params are irrelevant by
  # construction.
  KEYS = %w[range host programname severity text].freeze

  def initialize(params = {})
    @range = clean_range(params[:range])
    @host = clean(fetch(params, :host))
    @programname = clean(fetch(params, :programname))
    @severity = clean_severity(fetch(params, :severity))
    @text = clean(fetch(params, :text))&.truncate(MAX_TEXT_LENGTH)
  end

  # True when the user has narrowed the result set in any way. Used by the empty state to
  # tell "no logs at all" apart from "nothing matched your filters", which are very
  # different things to show a sysadmin.
  def filtered?
    [ host, programname, severity, text ].any?(&:present?)
  end

  # The "clear all filters" state, for the reset affordance.
  def self.default
    new({})
  end

  #
  # The field filters to AND together, in a fixed order so queries are deterministic and
  # assertable. Only catalog-known fields are emitted.
  #
  # @return [Array<String>] e.g. ["host:tern", "programname:sshd"]
  #
  def field_filters
    [
      ("host:#{quote_value(host)}" if host.present?),
      ("programname:#{quote_value(programname)}" if programname.present?),
      severity_filter
    ].compact
  end

  #
  # The severity filter as LogsQL, or nil when no level is selected.
  #
  # A level the picker offers directly (`err`, `warning`, ...) is a plain equality filter. A
  # GROUP term (`crit`) covers several raw levels, so it becomes an OR of equality filters:
  # LogsQL has no "or worse" operator, and the levels are not adjacent in a way `_time`-style
  # ranges could exploit, so the union has to be spelled out.
  #
  # Every term is expanded through the catalog rather than matched literally, so this stays
  # correct if the groups change.
  #
  def severity_filter
    return nil if severity.blank?

    levels = LogsFieldCatalog.severity_levels_for(severity)
    return nil if levels.empty?

    parts = levels.map { |level| "severity:#{quote_value(level)}" }
    # A single level needs no grouping; parentheses are added only where the OR would
    # otherwise bind against the neighbouring AND terms.
    parts.one? ? parts.first : "(#{parts.join(" OR ")})"
  end

  # The free-text term, or nil when unset.
  def text_term
    text.presence
  end

  #
  # The same state as URL params, for building links and the refresh URL without
  # repeating the key names at every call site.
  #
  # Override keys may be given as symbols or strings; they are stringified so callers do
  # not have to remember which, and so the result can go straight to `to_query`.
  #
  # @param overrides [Hash] merged on top (e.g. `{ range: "24h" }`), blank values dropped.
  #
  def to_params(overrides = {})
    base = { range: range, host: host, programname: programname, severity: severity, text: text }
    merged = base.merge(overrides.transform_keys(&:to_sym))
    merged.reject { |_k, v| v.nil? || v.to_s.empty? }.stringify_keys
  end

  #
  # Parse a client-supplied cursor into a Time, or nil when it is absent/invalid.
  #
  # The cursor is the `_time` of the newest row the browser already holds. It is echoed
  # back by the client on every poll, so it is untrusted input and is pattern-checked
  # before it reaches LogsQL.
  #
  def self.parse_cursor(value)
    raw = value.to_s.strip
    return nil if raw.empty?
    return nil unless ISO8601_PATTERN.match?(raw)

    Time.zone.parse(raw)
  rescue ArgumentError, TypeError
    nil
  end

  private

  # Read one known key from either a Hash (string or symbol keys) or
  # ActionController::Parameters. Reading key-by-key keeps unknown/unpermitted params out
  # of the picture entirely.
  def fetch(params, key)
    return nil if params.nil?

    params[key] || params[key.to_s]
  end

  def clean_range(value)
    candidate = value.to_s
    RANGE_OPTIONS.include?(candidate) ? candidate : DEFAULT_RANGE
  end

  #
  # Severity is validated against the catalog's FILTER terms rather than merely stripped.
  #
  # Unlike a hostname, which is free-form, a severity is a small closed set: the filter terms
  # the picker offers. Accepting anything else would send a `severity:` filter that cannot
  # match any record -- a filter that silently returns nothing is worse than no filter, because
  # the empty result reads as "no errors" rather than "you asked a bad question".
  #
  # The terms are not the raw levels: `crit` is a group covering crit/alert/emerg, and the
  # individual raw levels in that group are deliberately not accepted, since offering them
  # separately is what the grouping exists to avoid. What the menu can emit is exactly what
  # the parser accepts.
  #
  def clean_severity(value)
    candidate = clean(value)&.downcase
    return nil if candidate.nil?

    LogsFieldCatalog::SEVERITY_FILTER_TERMS.include?(candidate) ? candidate : nil
  end

  # Normalize a scalar param to a stripped String, or nil when blank/non-scalar. Arrays
  # and hashes are rejected outright: a repeated param (`?host=a&host=b`) should not
  # silently become a filter no one asked for.
  def clean(value)
    case value
    when nil then nil
    when String then value.strip.presence
    when Numeric, Symbol then value.to_s.strip.presence
    else nil
    end
  end

  # Escape a value used in a `field:value` LogsQL filter. Values with spaces or special
  # characters must be quoted or the expression parses as something else entirely.
  def quote_value(value)
    VictoriaLogs::Query.quote(value)
  end
end
