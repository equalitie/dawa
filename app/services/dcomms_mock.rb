#
# Canned dcommsctl responses — TEMPORARY.
#
# The dcommsctl backend does not yet implement `job/status`, `job/log` (real output),
# `job/list` or `inst/list`; see docs/dcommsctl-api-requests.md and
# docs/dcommsctl-integration-plan.md (§4, Step 1b).
#
# This class stands in for those methods so the rest of Dawa can be built and tested
# against the INTENDED contract. It implements the same signatures as DcommsClient and
# returns the same value objects, so DcommsAdapter can swap between them freely.
#
# RULES (see the plan):
#  * Return the *intended* shape from the API doc, never the current broken shape. If a
#    mock encoded today's bugs we would build against them and have to undo it later.
#  * Keep it deterministic and driveable: state advances only when a test calls
#    `advance!`, so there is no real sleeping and no flakiness.
#
# Every mocked method is marked `# MOCK(dcommsctl):` and names the API-requests section
# it stands in for, so unmocking can be verified by grep.
#
class DcommsMock
  # A scripted job, driven explicitly by tests (or DcommsJob) via `advance!`.
  class ScriptedJob
    attr_reader :id, :type, :instance_id, :chunks, :exit_code, :error

    #
    # @param running_for [Integer] how many `advance!` calls stay in "running" before
    #   reaching the terminal state. `1` means running on the first poll, done on the
    #   second.
    # @param terminal_state [String] terminal state, "done" or "failed".
    #
    def initialize(id:, type:, instance_id:, chunks: [], running_for: 1, terminal_state: "done",
                   exit_code: 0, error: nil)
      @id = id
      @type = type
      @instance_id = instance_id
      @chunks = chunks
      @running_for = running_for
      @terminal_state = terminal_state
      @exit_code = exit_code
      @error = error
      @state = "pending"
      @ticks = 0
      @served = 0
      @started_at = Time.now.utc
      @finished_at = nil
    end

    def advance!
      @ticks += 1
      @state = @ticks > @running_for ? @terminal_state : "running"
      @finished_at = Time.now.utc if terminal?
      self
    end

    def state = @state
    def terminal? = %w[done failed].include?(@state)

    # Bytes of log handed out so far.
    def served_bytes
      @chunks.first(@served).sum(&:bytesize)
    end

    # Hand out the next unserved chunk, or nil when caught up.
    def next_chunk
      chunk = @chunks[@served]
      @served += 1 if chunk
      chunk
    end

    def status
      Dcomms::JobStatus.new(
        id: id,
        type: type,
        instance_id: instance_id,
        state: state,
        exit_code: terminal? ? @exit_code : nil,
        error: terminal? ? @error : nil,
        bytes_written: served_bytes,
        started_at: @started_at.iso8601,
        finished_at: @finished_at&.iso8601
      )
    end
  end

  # MOCK(dcommsctl): inst/list (§E).
  #
  # Deterministic fixtures, including one row with a blank id/name. The real `apps/list`
  # has an equivalent zero-value-row bug, so the filtering rules must cope.
  DEFAULT_INSTANCES = [
    { "id" => "peertube-quokka", "app" => "peertube", "domain" => "peertube.test",
      "version" => "7.0.0", "status" => "running" },
    { "id" => "dawa-okapi", "app" => "dawa", "domain" => "dawa.test",
      "version" => "0.0.1", "status" => "running" },
    { "id" => "", "app" => "", "domain" => "", "version" => "", "status" => "" }
  ].freeze

  # A log long enough to need several offset-based polls, ending in a partial line (the
  # live-progress-bar case the byte cursor must tolerate).
  DEFAULT_LOG_CHUNKS = [
    "Cloning into 'peertube'...\n",
    "Resolving deltas: 100% (1234/1234), done.\n",
    "Running migrations...\n",
    "Starting containers...\n",
    "still working" # deliberately no trailing newline
  ].freeze

  def initialize(instances: DEFAULT_INSTANCES)
    @instances = instances
    @jobs = {}
    @order = []
  end

  # Register an already-built scripted job.
  def register(job)
    @jobs[job.id] = job
    @order << job.id
    job
  end

  # Build and register a job with defaults; returns it so a test can drive `advance!`.
  def script_job(id: "install-1", type: "install", instance_id: "peertube-quokka", **options)
    register(ScriptedJob.new(id: id, type: type, instance_id: instance_id, **options))
  end

  # --- mocked API surface ------------------------------------------------

  # MOCK(dcommsctl): job/status (§B).
  #
  # Advances the scripted job one step per call. An unknown job is an error, not a
  # zero-value success — matching the intended contract (job/status must not invent
  # state for a job it never had).
  def job_status(id:)
    job = fetch_job(id)
    job.advance!.status
  end

  # MOCK(dcommsctl): job/log (§C).
  #
  # Serves the next unserved chunk, honouring `offset` so the client's byte cursor is
  # genuinely exercised. A caller that is behind (offset < what we've served) gets an
  # empty chunk rather than a rewind, which mirrors "you already have these bytes".
  def job_log(id:, offset: 0)
    job = fetch_job(id)

    if offset < job.served_bytes
      return Dcomms::JobLog.new(log: "", next_offset: job.served_bytes, eof: true)
    end

    text = job.next_chunk.to_s
    Dcomms::JobLog.new(log: text, next_offset: job.served_bytes, eof: true)
  end

  # MOCK(dcommsctl): job/list (§D).
  def job_list(instance_id: nil, active_only: false)
    jobs = @order.map { |id| @jobs[id] }
    jobs = jobs.select { |job| job.instance_id == instance_id } if instance_id
    jobs = jobs.reject(&:terminal?) if active_only
    jobs.map(&:status)
  end

  # MOCK(dcommsctl): inst/list (§E).
  def instances_list
    @instances.filter_map { |raw| Dcomms::Instance.from_json(raw) }.select(&:available?)
  end

  private

  def fetch_job(id)
    @jobs[id] || raise(DcommsClient::ServerError.new(code: -32000, message: "unknown job: #{id}"))
  end
end
