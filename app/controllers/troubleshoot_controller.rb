class TroubleshootController < BaseAdminController
  def show
    @vm_diagnostic = vm_diagnostic
  end

  protected

  #
  # A few quick checks against VictoriaMetrics so an admin can see from the
  # troubleshoot page whether the app can reach it and whether it answers a simple
  # `up` query (and which instances/providers it reports).
  #
  # @return [Hash] :connected, :query_ok, :error, :providers
  #
  def vm_diagnostic
    service = VictoriaMetrics.new
    series = service.vector("up")
    {
      connected: true,
      query_ok: series.any?,
      error: nil,
      providers: providers_from(series)
    }
  rescue ErrorMessage, Prometheus::ApiClient::Client::RequestError, SocketError, Errno::ECONNREFUSED => e
    {
      connected: false,
      query_ok: false,
      error: e.message,
      providers: []
    }
  end

  def providers_from(series)
    series.filter_map do |s|
      metric = s["metric"] || {}
      instance = metric["instance"]
      value = s.dig("value", 1)
      next if instance.blank?
      { instance: instance, job: metric["job"], up: value == "1" }
    end
  end
end
