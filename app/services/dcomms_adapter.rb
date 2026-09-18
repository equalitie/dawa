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
  # Re-verified against the live daemon with `script/backend-ls` (see the plan's
  # "Probe results"). The list is short now because the daemon has implemented most of what
  # was missing:
  #
  #  * `job/status`        -> registered but a STUB. It returns a zero-value JobStatus and
  #                           never looks at the id, so a job that `job/list` reports as
  #                           `done` comes back with `state: ""`. Still the #1 backend ask.
  #  * `catalog_entry`     -> no `app/get` method exists; the catalog detail is not sent by
  #                           anything, so the show page's extra fields stay faked.
  #
  # `job/log`, `job/list` and `inst/list` are REAL now and are no longer mocked -- but see
  # the notes on each in DcommsClient, because two of them have sharp edges:
  #
  #  * `job/log` only works for a job that is still RUNNING. The daemon renames a finished
  #    job's log from `.partial.log` to `.log` but records the new path on the wrong map
  #    entry, so `job/log` fails with "no such file" for every completed job. Dawa cannot
  #    fix that; it is a daemon bug. Calls are still real because a progress view is only
  #    ever reading a running job.
  #  * `inst/list` is real and returns full rows now (id, app, domain, version, status).
  #    Note `version` is the CATALOG version, not what is actually running, and `status` is
  #    empty when docker compose cannot be reached.
  #
  #  * `job/list` is real and the daemon persists jobs to `.jobs_db.json`, reloading them
  #    on startup, so history survives a restart.
  #  * `job/status` is real now too: `rpcJobStatus` looks the id up via `statusByID` and
  #    errors for an unknown job, rather than returning a zero-value stub.
  #
  MOCKED = %i[catalog_entry].freeze

  # Fully-implemented methods, listed so tests can assert the split is deliberate.
  REAL = %i[catalog_list install uninstall start stop backup restore job_log job_list
            job_status apps_installed_list].freeze

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
  # MOCKED until the backend exposes a detail method. Note the asymmetry with
  # `catalog_list`, which is real: the list comes from the daemon, but the detail is
  # faked. That is why the show page must treat every detail field as optional.
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
  # Takes instance_id as well as the job id because the daemon keys its job map on the
  # pair; see DcommsClient#job_log.
  #
  def job_log(id:, instance_id:, offset: 0)
    if mocked?(:job_log)
      mock.job_log(id: id, instance_id: instance_id, offset: offset)
    else
      client.job_log(id: id, instance_id: instance_id, offset: offset)
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
