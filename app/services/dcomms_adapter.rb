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
#   4. grep for "MOCK(dcommsctl):" — there should be nothing left
#
class DcommsAdapter
  #
  # Methods the backend does not implement yet.
  #
  # Verified against the live daemon (docs/dcommsctl-integration-plan.md, "Probe results"):
  #  * `job/status`  -> JSON-RPC -32601 method not found
  #  * `inst/list`   -> JSON-RPC -32601 method not found
  #  * `job/list`    -> not registered
  #  * `job/log`     -> registered but STUBBED (always returns an empty string), so it
  #                     cannot be detected at runtime — hence this explicit list rather
  #                     than probing for support.
  #
  # `apps/list` and the `inst/*` mutations (excluding `upgrade`, which is a stub) ARE real.
  #
  MOCKED = %i[job_status job_log job_list instances_list].freeze

  # Fully-implemented methods, listed so tests can assert the split is deliberate.
  REAL = %i[apps_list install uninstall start stop backup restore].freeze

  def initialize(client: nil, mock: nil)
    @client = client
    @mock = mock
  end

  attr_reader :client, :mock

  # --- catalog (real) ----------------------------------------------------

  def apps_list
    mocked?(:apps_list) ? mock.apps_list : client.apps_list
  end

  # --- instances ---------------------------------------------------------

  def instances_list
    mocked?(:instances_list) ? mock.instances_list : client.instances_list
  end

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

  # --- jobs --------------------------------------------------------------

  # MOCKED until the backend implements `job/status`.
  def job_status(id:) = route(:job_status, id: id)

  # MOCKED while `job/log` is stubbed.
  def job_log(id:, offset: 0) = route(:job_log, id: id, offset: offset)

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
