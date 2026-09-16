#
# Single source of truth for which log fields the UI knows about.
#
module LogsFieldCatalog
  # Default column order for the host log table. Order matters: it is the render order.
  #
  # `severity` is first because it renders as a narrow colour stripe rather than a labelled
  # column: putting the level at the left edge makes a stream of logs scannable without
  # reading any text, which is the point of the field.
  HOST_FIELDS = [ :severity, :_time, :host, :programname, :priority, :_msg ].freeze

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
  # danger/warning, routine chatter as secondary, so the eye is drawn to what needs it.
  #
  # An unknown or missing level maps to nil, which the view renders as a neutral stripe
  # rather than guessing at a severity.
  #
  SEVERITY_COLORS = {
    "emerg" => "danger",
    "alert" => "danger",
    "crit" => "danger",
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
