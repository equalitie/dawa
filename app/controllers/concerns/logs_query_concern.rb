module LogsQueryConcern
  extend ActiveSupport::Concern

  included do
    helper_method :current_log_filters
  end

  #
  # The current filter state for this request.
  #
  def current_log_filters
    @current_log_filters ||= Logs::Filters.new(params)
  end

  # Fetch logs for the current filters.
  # A cursor narrows the query to `_time:(cursor, now]`.
  def fetch_logs(filters:, cursor: nil)
    cursor = nil unless usable_cursor?(cursor)
    log_service.query_lines(
      log_query(filters: filters, cursor: cursor),
      limit: max_log_lines
    )
  end

  # The newest `_time` in a batch, as an RFC3339 string, or nil when there is none.
  def newest_time(records)
    newest = records.filter_map { |r| r["_time"] }.max
    return nil if newest.blank?
    Time.zone.parse(newest)&.utc&.iso8601(6)
  rescue ArgumentError, TypeError
    # An unparseable timestamp must not advance the cursor, or we would skip logs forever.
    nil
  end

  #
  # One record as the JSON row the refresh endpoint returns.
  #
  # The row carries `cells`: one entry per visible column, in `LogsFieldCatalog` order,
  # already formatted. The client renders whatever it is given rather than knowing the
  # column list, so there is exactly one place that decides which columns exist and how
  # they look.
  #
  def log_row(record)
    {
      key: helpers.log_row_key(record),
      time: record["_time"],
      classes: helpers.log_row_cell_classes(record),
      cells: helpers.log_row_cells(record)
    }
  end

  private

  def log_service
    @log_service ||= VictoriaLogs.new
  end

  #
  # build the log query
  #
  def log_query(filters:, cursor: nil)
    VictoriaLogs.build_query(
      field_filters: filters.field_filters,
      text: filters.text_term,
      time_range: cursor ? nil : filters.range,
      cursor: cursor
    )
  end

  # True when a cursor is safe to query with.
  # The cursor is echoed back by the client, so it is untrusted.
  def usable_cursor?(cursor)
    cursor.present? && cursor <= Time.now.utc
  end

  # Never ask VictoriaLogs for more than the configured maximum.
  def max_log_lines
    [ Conf.logs_default_limit.to_i, Conf.logs_max_limit.to_i ].min
  end

end
