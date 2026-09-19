#
# The seam between Dawa and the dcommsctl backend.
#
# Controllers and jobs depend on THIS, never on DcommsClient or DcommsMock directly.
# It exists because the dcommsctl API is incomplete: some methods work today and go over
# a real WebSocket, while others are not implemented yet and are served by DcommsMock
# (see docs/dcommsctl-integration-plan.md §4, Step 1b).
#
# Real-by-default: calls the backend actually implements are always real. Only the
# methods in MOCKED are faked, and only while the daemon lacks them.
#
# Removing the mocks later (see the plan's "Removing the mocks"):
#   1. set Conf.dcomms_use_mocks to "none" (or delete the key)
#   2. delete DcommsMock and its test
#   3. empty MOCKED (the routing branches then vanish) or delete this class entirely
#   4. grep for "MOCK(dcommsctl):" -- there should be nothing left
#
class DcommsAdapter
  #
  # Methods served by DcommsMock instead of the daemon.
  #
  # EMPTY: the daemon now implements every method Dawa calls. `app/get` (the catalog detail)
  # was the last gap, added in rpc_app_get.go. DcommsMock is therefore unreachable through
  # this adapter in the default configuration, and the routing branches below are dead code
  # while the list stays empty.
  #
  # The list is kept (rather than deleted) because its emptiness is the signal that the
  # backend caught up: `DcommsAdapterTest` asserts it, and a method that regresses to a stub
  # would be added back here. Setting `dcomms_use_mocks` to "all" or a method list still
  # routes to the mock, which is how to work offline against fixtures.
  #
  # Sharp edges that remain in the REAL methods (none of them are missing methods):
  #
  #  * `job/log` only works for a job that is still RUNNING. The daemon renames a finished
  #    job's log from `.partial.log` to `.log` but records the new path on the wrong map
  #    entry, so `job/log` fails with "no such file" for every completed job. Dawa cannot
  #    fix that; it is a daemon bug.
  #  * `job/status` raises for an unknown id rather than returning a zero-value status.
  #  * `inst/list` is real and returns full rows (id, app, domain, version, status). Note
  #    `version` is the CATALOG version, not what is actually running, and `status` is empty
  #    when docker compose cannot be reached.
  #  * `job/list` reports jobs persisted to `.jobs_db.json`, reloaded on daemon startup, so
  #    history survives a restart.
  #
  MOCKED = [].freeze

  # Fully-implemented methods, listed so tests can assert the split is deliberate.
  REAL = %i[catalog_list catalog_entry install uninstall start stop backup restore job_log
            job_list job_status apps_installed_list].freeze

  def initialize(client: nil, mock: nil)
    # Default to the real collaborators. Without this, `DcommsAdapter.new` (which is how the
    # controllers build it) would have a nil client and nil mock, and every call would fail
    # with "undefined method ... for nil".
    @client = client || DcommsClient.new
    @mock = mock || DcommsMock.new
  end

  attr_reader :client, :mock

  ##
  ## catalog (real)
  ##

  #
  # The catalog of installable entries.
  #
  # Named for what it returns (catalog entries, the things that CAN be installed) rather
  # than the backend's method name (`app/list`, which sounds like installed apps).
  #
  def catalog_list
    mocked?(:catalog_list) ? mock.catalog_list : client.catalog_list
  end

  #
  # One catalog entry, with the detail the index does not carry (long description,
  # upstream and definition URLs, release history).
  #
  # Real: `app/get` returns an `ApplicationDetail` (rpc_app_get.go), which embeds the same
  # summary shape as `app/list`, so the two cannot drift on the daemon side. Every detail
  # field is still treated as optional by the view, because the daemon omits empty ones
  # (`omitempty`) and an entry can legitimately have no releases.
  #
  def catalog_entry(id:)
    if mocked?(:catalog_entry)
      mock.catalog_entry(id: id)
    else
      client.catalog_entry(id: id)
    end
  end

  # Old names, kept so nothing breaks mid-refactor.
  alias_method :definitions_list, :catalog_list
  alias_method :apps_list, :catalog_list

  ##
  ## apps (installed)
  ##

  #
  # Installed apps. Real: `inst/list` is implemented and returns full rows (id, app,
  # domain, version, status). `status` is empty when the daemon cannot reach docker
  # compose, which means unknown -- see DcommsClient#apps_installed_list.
  #
  def apps_installed_list
    mocked?(:apps_installed_list) ? mock.apps_installed_list : client.apps_installed_list
  end

  # Old name, kept so nothing breaks mid-refactor.
  alias_method :instances_list, :apps_installed_list

  def install(name:, domain:)
    if mocked?(:install)
      mock.install(name: name, domain: domain)
    else
      client.install(name: name, domain: domain)
    end
  end

  def uninstall(id:) = route(:uninstall, id: id)
  def start(id:) = route(:start, id: id)
  def stop(id:) = route(:stop, id: id)
  def backup(id:) = route(:backup, id: id)
  def restore(id:) = route(:restore, id: id)

  ##
  ## jobs
  ##

  # `job/status` - a job's state. Real (the daemon implements `statusByID`).
  #
  # It raises for an unknown job id rather than inventing a state, so a caller must handle
  # "no such job" as a distinct outcome from "the backend did not answer".
  #
  def job_status(id:) = route(:job_status, id: id)

  # Real, with a caveat: the daemon only serves the log of a RUNNING job. A finished job's
  # log is renamed to `.log` while the recorded path keeps saying `.partial.log`, so this
  # fails with "no such file" once the job completes. That is a daemon bug, not something
  # the client can work around -- and harmless for the intended use, which is watching a job
  # that is in flight.
  #
  # Takes only the job id: the daemon resolves the instance itself. See DcommsClient#job_log.
  #
  def job_log(id:, offset: 0)
    if mocked?(:job_log)
      mock.job_log(id: id, offset: offset)
    else
      client.job_log(id: id, offset: offset)
    end
  end

  # Real. Jobs are persisted to `.jobs_db.json` and reloaded on daemon startup
  # (`loadJobs`), so this reports history as well as live work.
  #
  def job_list(instance_id: nil, active_only: false)
    if mocked?(:job_list)
      mock.job_list(instance_id: instance_id, active_only: active_only)
    else
      client.job_list(instance_id: instance_id, active_only: active_only)
    end
  end

  # True when the given method is currently served by the mock.
  def mocked?(method_name)
    mocked_methods.include?(method_name.to_sym)
  end

  # The set of methods currently served by the mock, resolved from configuration.
  #
  # `Conf.dcomms_use_mocks` accepts:
  #   "default"  -> MOCKED (the known-missing set)
  #   "none"     -> nothing mocked (use once the API lands)
  #   "all"      -> the whole surface, for offline UI work
  #   "a,b,c"    -> an explicit list of method names
  def mocked_methods
    @mocked_methods ||= resolve_mocked_methods
  end

  private

  # Forward a simple (id-keyword-only) call to the mock or the real client.
  #
  # Kept as one helper so the mocked and real paths cannot silently take different
  # arguments for the same method.
  def route(method_name, **args)
    mocked?(method_name) ? mock.public_send(method_name, **args) : client.public_send(method_name, **args)
  end

  def resolve_mocked_methods
    raw = Conf.dcomms_use_mocks.to_s.strip

    case raw
    when "", "default" then MOCKED
    when "none" then []
    when "all" then (MOCKED + REAL).uniq
    else raw.split(",").map(&:strip).reject(&:empty?).map(&:to_sym)
    end
  end
end
