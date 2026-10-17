#
# Single source of truth for which log fields the UI knows about.
#
module Logs::FieldCatalog
  # Default column order for the host log table. Order matters: it is the render order.
  #
  # `severity` is first because it renders as a narrow colour stripe rather than a labelled
  # column: putting the level at the left edge makes a stream of logs scannable without
  # reading any text, which is the point of the field.
  #
  # `priority` is deliberately NOT a column. It is the same fact as `severity` in another
  # encoding (journald's numeric PRIORITY -- see the transform in vector.yml), so showing both
  # prints the same level twice, once as a stripe and once as a number. The record still
  # carries it, and it still appears in the message cell's field list, so nothing is lost.
  #
  # `host` is deliberately NOT a column either. Dawa is single-host, so every row carries the
  # same value and the column is pure width. The machine is still identifiable from the page,
  # and the Source column carries what does vary (see `log_context` / `log_source`).
  #
  # `context` and `programname` are SYNTHETIC columns: neither is a field on the record, both
  # are derived (`log_context` and `log_source` respectively). They are named here anyway
  # because the catalog is what decides which columns exist and in what order, and splitting
  # the two parts of the old single Source cell into adjacent columns is a display decision
  # that belongs with the rest.
  # `programname` keeps its name because the label it shows IS the program for a host log; the
  # key predates the split and the label is what the user reads.
  HOST_FIELDS = [ :severity, :_time, :context, :programname, :_msg ].freeze

  #
  # Columns derived from a record rather than read off it.
  #
  # `context` comes from `log_context` (the container name) and `programname` happens to
  # coincide with a real journald field, so the two differ: `programname` IS emitted, `context`
  # is NOT. Anything reconciling this catalog against the fields a deployment actually emits
  # must ignore the derived ones, or it would report a fabricated column for every host.
  #
  SYNTHETIC_FIELDS = [ :context ].freeze

  # Fields that may be offered as filters for host logs.
  # These map to host sink `_stream_fields` (`host,programname`) plus `severity`,
  # so narrowing on them stays cheap.
  HOST_FILTERABLE = [ :host, :programname, :severity ].freeze

  #
  # Columns that render without a heading.
  #
  # `severity` carries its meaning entirely in colour, so a text label would be both
  # redundant and noisy. Keeping this set alongside the field list means the header and the
  # cells cannot disagree about which columns are labelled.
  #
  UNLABELLED_FIELDS = [ :severity ].freeze

  #
  # Severity level to bootstrap colour name.
  #
  # Keys are the standard syslog level names that `to_syslog_level` emits from journald's
  # numeric PRIORITY (0 = emerg ... 7 = debug), which is how `severity` is derived in the
  # vector transform. The scale is deliberately loud-to-quiet: panics and failures read as
  # danger/dark, routine chatter as secondary, so the eye is drawn to what needs it.
  #
  # An unknown or missing level maps to nil, which the view renders as a neutral stripe
  # rather than guessing at a severity.
  #
  SEVERITY_COLORS = {
    "emerg" => "dark",
    "alert" => "dark",
    "crit" => "dark",
    "err" => "danger",
    "error" => "danger", # accepted alias; not emitted by to_syslog_level
    "warning" => "warning",
    "warn" => "warning", # accepted alias
    "notice" => "info",
    "info" => "success",
    "debug" => "secondary"
  }.freeze

  # The bootstrap colour for a severity value, or nil when it is not a known level.
  def self.severity_color(value)
    SEVERITY_COLORS[value.to_s.downcase.strip]
  end

  #
  # The levels the severity FILTER offers, as filter terms mapped to the raw levels each one
  # covers.
  #
  # `crit` is a group rather than a single level: it stands for "crit or worse" (crit, alert,
  # emerg), which is how triage actually reads. Those three are rare on a healthy host and
  # indistinguishable at stripe width, so offering them separately asked the user to pick
  # between options they have no basis to choose. `err` stays on its own because it is the
  # one level that is both common and actionable -- "did anything actually fail" -- and
  # folding it into a group would make that question unaskable.
  #
  # Order is most severe first, which is the order a triage workflow reads in.
  #
  SEVERITY_FILTERS = {
    "crit" => %w[crit alert emerg],
    "err" => %w[err],
    "warning" => %w[warning],
    "notice" => %w[notice],
    "info" => %w[info],
    "debug" => %w[debug]
  }.freeze

  # The filter terms the picker offers, worst first.
  SEVERITY_FILTER_TERMS = SEVERITY_FILTERS.keys.freeze

  #
  # The raw levels a filter term covers, or an empty array when the term is unknown.
  #
  # Callers use this to build the query rather than matching the term literally, so `crit`
  # finds records stored as `alert` or `emerg` too.
  #
  def self.severity_levels_for(term)
    SEVERITY_FILTERS[term.to_s.downcase.strip] || []
  end

  #
  # The `text-bg-*` class for a severity value.
  #
  # An unknown or missing level gets the neutral colour rather than no class, so the stripe
  # is still drawn and every row keeps the same column width.
  #
  def self.severity_class(color)
    "text-bg-#{color.presence || 'secondary'}"
  end

  # True when the column should render without a heading.
  def self.unlabelled?(field)
    UNLABELLED_FIELDS.include?(field.to_sym)
  end

  #
  # True when `field` is part of the given tier's known columns. Accepts strings or
  # symbols (records come back from JSON with string keys).
  #
  def self.displayable?(field, tier: :host)
    known(tier).include?(field.to_sym)
  end

  # True when a field may be suggested as a filter for the given tier.
  def self.filterable?(field, tier: :host)
    filterable(tier).include?(field.to_sym)
  end

  def self.known(tier)
    case tier.to_sym
    when :host then HOST_FIELDS
    else []
    end
  end

  def self.filterable(tier)
    case tier.to_sym
    when :host then HOST_FILTERABLE
    else []
    end
  end
end
