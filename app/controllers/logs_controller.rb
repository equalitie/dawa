#
# Log explorer backed by VictoriaLogs.
#
# `index` renders the initial page (filters + the newest window of logs). `data` serves the
# JSON the explorer refreshes from, and returns *only* JSON -- the browser diffs and
# appends, so no HTML is regenerated per poll.
#
# Filter state lives in `LogsFilters` and LogsQL is assembled by `VictoriaLogs::Query`.
# The browser never composes either; it echoes state back as params. That keeps quoting and
# escaping in one place, which is the whole reason Step 4 forbids LogsQL in JS.
#
class LogsController < BaseAdminController
  include Logs::Helper
  include Logs::TableHelper
  helper Logs::Helper

  def index
    @filters = current_filters
    @logs = fetch_logs
    # Seed the client's cursor from the newest row we just rendered, so the first poll asks
    # only for what arrived after this page load. Without it the first poll would refetch
    # the whole window and rely purely on client-side dedupe.
    @cursor = newest_time(@logs)
  rescue VictoriaLogs::RequestError, Faraday::Error => e
    @logs = []
    @cursor = nil
    @error = e.message
  end

  #
  # JSON refresh endpoint.
  #
  # With no `cursor`, this is a plain query over the selected window (what the initial page
  # shows). With a cursor, it narrows to `_time:(cursor, now]` so only logs the browser
  # cannot already have are transferred.
  #
  def data
    @filters = current_filters
    cursor = LogsFilters.parse_cursor(params[:cursor])

    records = fetch_logs(cursor: cursor)
    render json: {
      rows: records.map { |record| log_row(record) },
      # The newest time in this batch, echoed so the client can advance its cursor without
      # parsing timestamps itself (it must not, since it cannot know the server's zone).
      cursor: newest_time(records) || params[:cursor].presence,
      # Lets the client distinguish "caught up, nothing new" from "the query failed", which
      # otherwise both look like an empty array.
      count: records.size
    }
  rescue VictoriaLogs::RequestError, Faraday::Error => e
    # A refresh failure must not look like "no new logs": that would silently hide an
    # outage. The client shows a degraded state instead.
    render json: { rows: [], error: e.message }, status: :bad_gateway
  end

  private

  #
  # Fetch logs for the current filters.
  #
  # A cursor narrows the query to `_time:(cursor, now]`. A cursor we will not use (see
  # `usable_cursor?`) is DROPPED rather than treated as "no results": falling back to the
  # window query still shows logs, which is the useful behaviour when the client's clock
  # is wrong.
  #
  def fetch_logs(cursor: nil)
    cursor = nil unless usable_cursor?(cursor)
    service.query_lines(query(cursor: cursor), limit: limit)
  end

  def query(cursor: nil)
    VictoriaLogs.build_query(
      field_filters: @filters.field_filters,
      text: @filters.text_term,
      time_range: cursor ? nil : @filters.range,
      cursor: cursor
    )
  end

  def service
    @service ||= VictoriaLogs.new
  end

  # Never ask VictoriaLogs for more than the configured maximum.
  def limit
    [ Conf.logs_default_limit.to_i, Conf.logs_max_limit.to_i ].min
  end

  #
  # True when a cursor is safe to query with.
  #
  # The cursor is echoed back by the client, so it is untrusted. A clock skew or a
  # hand-edited value could put it ahead of the server, and `_time:(future, now]` is an
  # empty-to-invalid interval. Rejecting the cursor (rather than the whole request) falls
  # back to the window query, which still shows logs.
  #
  def usable_cursor?(cursor)
    cursor.present? && cursor <= Time.now.utc
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
end
