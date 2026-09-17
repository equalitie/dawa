require "faraday"
require "docker_engine_ruby"

class TroubleshootController < BaseAdminController
  def show
    @vm_diagnostic = vm_diagnostic
    @vl_diagnostic = vl_diagnostic
    @docker_diagnostic = docker_diagnostic
    @dcomms_diagnostic = dcomms_diagnostic
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

  #
  # A reachability check against VictoriaLogs, plus the number of fields it knows about.
  #
  # `field_names` is the cheapest endpoint that still proves the LogsQL API works: it needs
  # no pipes, returns quickly even on a large store, and a non-empty answer shows that logs
  # are actually being ingested (a reachable-but-empty VictoriaLogs and an unreachable one
  # are different problems, and the explorer looks equally blank in both).
  #
  # The `*` query is required, not decorative: VictoriaLogs answers 400 to
  # `/select/logsql/field_names` with no `query` arg at all, so a bare call reads as a
  # failure. `*` is LogsQL for "match every log".
  #
  # @return [Hash] :connected, :field_count, :error
  #
  def vl_diagnostic
    fields = vl_service.field_names("*")
    {
      connected: true,
      field_count: fields.size,
      error: nil
    }
  rescue VictoriaLogs::RequestError, Faraday::Error, SocketError, Errno::ECONNREFUSED => e
    # VictoriaLogs#get re-raises connection/timeout failures as their Faraday class and
    # wraps a bad *response* as RequestError; both mean "cannot use it", which is all this
    # page reports, so they share the unreachable branch.
    {
      connected: false,
      field_count: 0,
      error: e.message
    }
  end

  #
  # A check against the Docker Engine API.
  #
  # `version` is preferred over `ping` because it proves the daemon is not just listening
  # but speaking the API, and it gives an admin the API version to compare against the
  # client -- a version mismatch is a real failure mode here and otherwise surfaces as a
  # confusing error on the containers page.
  #
  # @return [Hash] :connected, :version, :api_version, :error
  #
  def docker_diagnostic
    version = docker_client.system_.version
    {
      connected: true,
      version: version.version,
      api_version: version.api_version,
      error: nil
    }
  rescue DockerEngineRuby::Errors::Error => e
    {
      connected: false,
      version: nil,
      api_version: nil,
      error: docker_error_message(e)
    }
  end

  #
  # A reachability check against dcommsctl.
  #
  # `job/list` is the probe: it is the only non-mutating method that needs no prior
  # knowledge (a `job/status` id would have to come from somewhere, and every `inst/*`
  # method allocates a lock even when it does nothing -- see script/backend-ls). Its reply
  # also shows how many jobs the daemon is currently tracking.
  #
  # The adapter is used, not DcommsClient, so the check exercises the same seam the app
  # does. `job_list` is in DcommsAdapter::REAL, so this always reaches the daemon regardless
  # of the `dcomms_use_mocks` setting.
  #
  # @return [Hash] :connected, :job_count, :error
  #
  def dcomms_diagnostic
    jobs = adapter.job_list
    {
      connected: true,
      job_count: jobs.size,
      error: nil
    }
  rescue DcommsClient::Error, SocketError, Errno::ECONNREFUSED, IO::TimeoutError => e
    {
      connected: false,
      job_count: 0,
      error: e.message
    }
  end

  # The Docker gem's connection errors carry a nested `cause` (a raw socket error) whose
  # message is the useful one; the exception's own message is often just "Connection
  # error." See ContainersController, which unwraps it the same way.
  def docker_error_message(error)
    case error
    when DockerEngineRuby::Errors::APIConnectionError
      [ "Could not connect to Docker", error.cause&.message ].compact.join(": ")
    else
      error.message
    end
  end

  # The VictoriaLogs client this controller checks with. Split out so the probe can be
  # exercised without a socket.
  def vl_service
    @vl_service ||= VictoriaLogs.new
  end

  def docker_client
    @docker_client ||= DockerEngineRuby::Client.new(
      max_retries: 2,
      timeout: 10,
      base_url: Conf.docker_url
    )
  end

  # Never talk to DcommsClient directly; the adapter owns the real/mock decision.
  def adapter
    @adapter ||= DcommsAdapter.new
  end
end
