#
# Log explorer backed by VictoriaLogs.
#
# `index` renders the initial page (filters + the newest window of logs). `data` serves the
# JSON the explorer refreshes from, and returns *only* JSON -- the browser diffs and
# appends, so no HTML is regenerated per poll.
#
# Filter state lives in `Logs::Filters` and LogsQL is assembled by `Logs::Query`.
# The browser never composes either; it echoes state back as params. That keeps quoting and
# escaping in one place, which is the whole reason Step 4 forbids LogsQL in JS.
#
class LogsController < BaseAdminController
  include LogsQueryConcern
  include Logs::TableHelper
  #helper "logs/helper" #Logs::Helper

  def index
    @filters = current_log_filters
    @logs = fetch_logs(filters: @filters, cursor: nil)
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
    @filters = current_log_filters
    cursor = Logs::Filters.parse_cursor(params[:cursor])
    records = fetch_logs(filters: @filters, cursor: cursor)
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

end
