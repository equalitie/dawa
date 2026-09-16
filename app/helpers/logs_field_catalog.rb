#
# Single source of truth for which log fields the UI knows about.
#
module LogsFieldCatalog
  # Default column order for the host log table. Order matters: it is the render order.
  HOST_FIELDS = [ :_time, :host, :programname, :unit, :severity, :priority, :_msg ].freeze

  # Fields that may be offered as filters for host logs.
  # These map to host sink `_stream_fields` (`host,programname,unit`) plus `severity`,
  # so narrowing on them stays cheap.
  HOST_FILTERABLE = [ :host, :programname, :unit, :severity ].freeze

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
