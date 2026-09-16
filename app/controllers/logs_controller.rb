#
# Log explorer backed by VictoriaLogs.
#
class LogsController < BaseAdminController
  include LogsHelper

  def index
    @range = logs_range
    @logs = fetch_logs
  rescue VictoriaLogs::RequestError, Faraday::Error => e
    @logs = []
    @error = e.message
  end

  private

  def fetch_logs
    service.query_lines(query, limit: limit)
  end

  def query
    VictoriaLogs.build_query(time_range: @range)
  end

  def service
    @service ||= VictoriaLogs.new
  end

  # Never ask VictoriaLogs for more than the configured maximum.
  def limit
    [ Conf.logs_default_limit.to_i, Conf.logs_max_limit.to_i ].min
  end
end
