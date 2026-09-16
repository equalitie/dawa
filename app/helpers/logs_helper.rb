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
  # Both Context and Source columns read the SAME question -- "what logged this, and which one
  # is it" -- but each column shows one half, so they are two methods rather than one returning
  # a pair. The split has to agree on one thing: whether the record is a container record.
  # `container_record?` is that test, and both go through it so the columns cannot disagree
  # about which half a row belongs to (one column showing a container context beside a host
  # source would be nonsense).
  #
  def log_context(record)
    if container_record?(record)
      # An INSTALLATION of an app: `dc_inst` says which one ("dummy-1" when an app runs several
      # instances). Falls back to `dc_app` so a container labeled before `dc_inst` existed still
      # gets a context rather than an empty one.
      record["dc_inst"].presence || record["dc_app"].presence
    else
      # The machine itself. There is nothing finer to name at this level -- the daemon goes in
      # the Source column beside it.
      "host"
    end
  end

  #
  # The specific source within the context, most human-readable first.
  #
  # `dc_name` is a friendly per-instance label -- PLANNED but not emitted yet, so this lookup
  # currently falls through to `container_name`, the compose service (e.g. "dawa-web-1").
  # `container_id` is the last resort, and is SHORTENED: a full 64-hex id is unreadable in a
  # table cell, and two containers of one app are told apart by their first few characters
  # anyway.
  #
  # On the host side the chain is the daemon, then the systemd unit, then the machine name --
  # progressively less specific, but each still identifies the row, and a weak label beats a
  # blank one.
  #
  # @return [String, nil] nil when nothing names the record (an unnamed container).
  #
  def log_source(record)
    if container_record?(record)
      record["dc_name"].presence || record["container_name"].presence ||
        short_container_id(record["container_id"])
    else
      record["programname"].presence || record["unit"].presence || record["host"].presence
    end
  end

  #
  # True when a record came from a container rather than from the host itself.
  #
  # Keyed on the Dawa labels rather than on `source_type` or the presence of a container name:
  # the labels are what the composer sets for an installed app, and they are what the two
  # columns above are really describing.
  #
  def container_record?(record)
    record["dc_app"].present? || record["dc_inst"].present?
  end

  #
  # A container id shortened for display: Docker's own convention is the first 12 hex
  # characters, which is what `docker ps` shows and what users recognize.
  #
  def short_container_id(id)
    value = id.to_s.presence
    return nil if value.nil?

    value[0, 12]
  end

  ##
  ## Source colour
  ##

  # Saturation and lightness for source badges, as percentages (`hsl()` takes them that way).
  # Fixed, so every badge has the same visual weight and only the HUE varies -- varying
  # brightness too would read as meaning ("dimmer = less important") that is not there, and
  # would make some labels harder to read than others for no reason.
  SOURCE_BADGE_SATURATION = 80
  SOURCE_BADGE_LIGHTNESS = 80

  #
  # The hue range source badges are spread over, in degrees.
  #
  # Deliberately NOT the full 0..360 wheel: the wheel wraps, so 0 and 359 are both red and two
  # unrelated programs would land on nearly the same colour at the seam. Restricting the range
  # trades a little room between neighbours for never having a false "these two are the same".
  #
  # 30..330 also skips the pure reds around 0, which at this lightness are the hardest to tell
  # from orange and from each other.
  #
  SOURCE_HUE_MIN = 30
  SOURCE_HUE_SPAN = 300

  #
  # A stable colour for a source label, as CSS `hsl()`.
  #
  # The point is that the same string always gets the same colour, in this request and every
  # later one, so a reader learns "peertube is the blue one" and can scan for it. That rules
  # out anything random or counter-based: the colour has to be a pure function of the text.
  #
  # The hash is a POSITION-WEIGHTED sum of the character ordinals: each character is
  # multiplied by its 1-based index, then the products are added. A plain sum is
  # order-insensitive, which made anagrams collide exactly -- `sshd` and `cron` are the same
  # eight-or-so characters' worth of ordinals and landed on identical hues, and short names
  # clustered because their sums all fall in a narrow band. Weighting by position fixes both
  # at the same cost: still one pass over a short string, still no allocation.
  #
  # It is deliberately NOT cryptographic: a collision means two programs share a colour, which
  # is a cosmetic annoyance rather than a correctness problem, so an avalanche hash would buy
  # nothing for that risk.
  #
  # Returns nil for a blank label so the caller can fall back to a plain badge rather than
  # rendering an invisible one: a hash of "" would otherwise produce a valid-looking colour
  # for a badge with nothing in it.
  #
  # @return [String, nil] e.g. "hsl(210 80% 80%)"
  #
  def source_label_color(label)
    text = label.to_s
    return nil if text.empty?

    hue = SOURCE_HUE_MIN + (weighted_ordinal_sum(text) % SOURCE_HUE_SPAN)
    "hsl(#{hue} #{SOURCE_BADGE_SATURATION}% #{SOURCE_BADGE_LIGHTNESS}%)"
  end

  #
  # A position-weighted sum of a string's character ordinals.
  #
  # See `source_label_color` for why the weight is needed. `each_char.with_index(1)` so the
  # first character counts once rather than zero, which keeps a leading character from being
  # free and two strings differing only there from colliding.
  #
  def weighted_ordinal_sum(text)
    text.each_char.with_index(1).sum { |char, index| char.ord * index }
  end

  # A short, single-line preview of the message body.
  def log_message(record, length: 160)
    record["_msg"].to_s.truncate(length)
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
