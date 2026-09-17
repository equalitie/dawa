#
# Canned dcommsctl responses -- TEMPORARY.
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
  DEFAULT_APPS = [
    { "id" => "peertube-quokka", "app" => "peertube", "domain" => "peertube.test",
      "version" => "7.0.0", "status" => "running" },
    { "id" => "dawa-okapi", "app" => "dawa", "domain" => "dawa.test",
      "version" => "0.0.1", "status" => "running" },
    { "id" => "", "app" => "", "domain" => "", "version" => "", "status" => "" }
  ].freeze

  #
  # MOCK(dcommsctl): the detail half of apps/list.
  #
  # `apps/list` returns only id/name/version/redirect_uri, so everything the catalog
  # *show* page needs (long description, upstream and definition URLs, the release
  # history) is absent. The real implementation should return these per entry; until it
  # does, anything missing is filled with deterministic Faker text so the page can be
  # built and reviewed.
  #
  # Release histories are shaped to exercise the UI: one entry with many releases, one
  # with a single release, and none with an empty history, so the "no releases" branch
  # is reachable without hand-editing fixtures.
  #
  # Faker is seeded per entry id, so the same entry always produces the same text. That
  # keeps tests and screenshots stable while still reading like real prose.
  #
  RELEASE_COUNTS = { "peertube" => 5, "mastodon" => 3, "dawa" => 1 }.freeze

  # A log long enough to need several offset-based polls, ending in a partial line (the
  # live-progress-bar case the byte cursor must tolerate).
  DEFAULT_LOG_CHUNKS = [
    "Cloning into 'peertube'...\n",
    "Resolving deltas: 100% (1234/1234), done.\n",
    "Running migrations...\n",
    "Starting containers...\n",
    "still working" # deliberately no trailing newline
  ].freeze

  def initialize(apps: DEFAULT_APPS)
    @apps = apps
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

  ##
  ## mocked API surface
  ##

  # MOCK(dcommsctl): job/status (§B).
  #
  # Advances the scripted job one step per call. An unknown job is an error, not a
  # zero-value success -- matching the intended contract (job/status must not invent
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
  #
  # Takes `instance_id` as well as the job id because the daemon keys its job map on the
  # pair; see DcommsClient#job_log.
  #
  def job_log(id:, instance_id:, offset: 0)
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
  def apps_installed_list
    @apps.filter_map { |raw| Dcomms::AppInstance.from_json(raw) }.select(&:available?)
  end

  # Old name, kept so nothing breaks mid-refactor.
  alias_method :instances_list, :apps_installed_list

  # MOCK(dcommsctl): catalog entry detail (the unwritten `apps/get`).
  #
  # Decorates one entry from `apps/list` with the metadata the show page needs. Returning
  # a CatalogEntry rather than raw JSON keeps the same value-object contract as the real
  # client, so the view cannot tell the two apart.
  #
  # @param id [String] the catalog entry id.
  # @raise [DcommsClient::ServerError] for an unknown id, matching `job/status`'s rule
  #   that the backend must not invent state for something it never had.
  #
  def catalog_entry(id:)
    raw = catalog_raw(id)
    raise DcommsClient::ServerError.new(code: -32000, message: "unknown catalog entry: #{id}") if raw.nil?

    Dcomms::CatalogEntry.new(
      id: raw["id"],
      name: raw["name"],
      version: latest_version_for(raw["id"]),
      redirect_uri: raw["redirect_uri"],
      description: raw["description"],
      long_description: long_description_for(raw),
      upstream_url: UPSTREAM_URLS[raw["id"]] || "https://example.invalid/#{raw["id"]}",
      definition_url: DEFINITION_URLS[raw["id"]] || "https://example.invalid/dcomms-apps/#{raw["id"]}",
      updated_at: updated_at_for(raw["id"]),
      releases: releases_for(raw["id"])
    )
  end

  private

  def fetch_job(id)
    @jobs[id] || raise(DcommsClient::ServerError.new(code: -32000, message: "unknown job: #{id}"))
  end

  # The catalog itself is real; these are the extra entries the detail mock can describe.
  CATALOG_FIXTURES = [
    { "id" => "peertube", "name" => "Peertube",
      "description" => "A federated video platform." },
    { "id" => "mastodon", "name" => "Mastodon",
      "description" => "A federated social network." },
    { "id" => "dawa", "name" => "DAWA", "description" => "Web admin for your server." }
  ].freeze

  UPSTREAM_URLS = {
    "peertube" => "https://joinpeertube.org",
    "mastodon" => "https://joinmastodon.org",
    "dawa" => "https://example.invalid/dawa"
  }.freeze

  DEFINITION_URLS = {
    "peertube" => "https://example.invalid/dcomms-apps/peertube",
    "mastodon" => "https://example.invalid/dcomms-apps/mastodon",
    "dawa" => "https://example.invalid/dcomms-apps/dawa"
  }.freeze

  def catalog_raw(id)
    CATALOG_FIXTURES.detect { |entry| entry["id"] == id.to_s }
  end

  # The real `long_description` is prose, so the fixture is too: a lead sentence plus
  # several paragraphs. Passing count: 1 here produced a one-paragraph "long" description,
  # which made the show page look like it was truncating.
  def long_description_for(raw)
    "#{raw["description"]} #{CatalogPlaceholderText.paragraphs("#{raw["id"]}-long")}"
  end

  def updated_at_for(id)
    # Spread entries over the recent past so "updated" ordering is visible, and keep it
    # deterministic (a fixed anchor, not Time.now) so tests do not drift.
    days_ago = (id.to_s.bytes.sum % 30) + 1
    (MOCK_NOW - days_ago.days).iso8601
  end

  def latest_version_for(id)
    releases_for(id).first&.version
  end

  # Descending semver-ish history, newest first. The count is fixed per entry so the
  # same entry always gets the same list.
  def releases_for(id)
    count = RELEASE_COUNTS[id.to_s].to_i
    return [] if count.zero?

    (0...count).map do |index|
      Dcomms::Release.new(
        version: "#{count - index}.0.0",
        released_at: (MOCK_NOW - (index * 45).days).iso8601,
        changelog: CatalogPlaceholderText.tagline("#{id}-#{index}")
      )
    end
  end

  # A stable anchor for generated dates. Deliberately not Time.now: fixtures must not
  # change between runs.
  MOCK_NOW = Time.zone.parse("2026-01-01T00:00:00Z").freeze
end
