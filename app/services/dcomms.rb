#
# Value objects for the dcommsctl JSON-RPC backend.
#
# dcommsctl returns plain JSON; these wrap it so callers (controllers, jobs, views)
# never poke at raw Hashes with string keys, and so the intended contract from
# docs/dcommsctl-api-requests.md lives in one place per shape.
#
# Vocabulary. Two words are deliberately kept apart, and the mapping from dcommsctl's
# method names is confined to the client:
#
#   dcommsctl method   Dawa concept    meaning
#   app/list           CatalogEntry    what CAN be installed (Peertube, an IMAP server)
#   inst/list          App             what IS installed (one deployment, own data)
#
# So in Dawa, "app" always means an installed thing, never a catalog entry. dcommsctl uses
# "app" for both, and `dc_app` labels a container with the catalog entry it came from,
# which is why the translation is spelled out rather than assumed.
#
# A catalog entry has zero or more apps.
#
module Dcomms
  #
  # One release of a catalog entry: a specific version, published at a specific time.
  #
  # A release is what an app instance is pinned to. Per notes/todo.md an app version is
  # "a specific set of the container image versions that make up that release", declared
  # together, and it may carry its own backup/restore/upgrade scripts -- so this is the
  # unit that upgrade paths are expressed between, not a cosmetic label.
  #
  # Only `version` is required. `released_at` is part of the intended contract but is not
  # sent yet; callers must tolerate nil and should not invent a date.
  #
  class Release
    attr_reader :version, :released_at, :changelog

    def initialize(version:, released_at: nil, changelog: nil)
      @version = version.to_s
      @released_at = parse_time(released_at)
      @changelog = changelog.presence
    end

    def self.from_json(raw)
      return nil unless raw.is_a?(Hash)
      return nil unless raw["version"].present?

      new(version: raw["version"], released_at: raw["released_at"], changelog: raw["changelog"])
    end

    def released? = released_at.present?

    def to_s = version

    private

    def parse_time(value)
      case value
      when nil then nil
      when Time, DateTime then value
      when String then Time.zone.parse(value)
      end
    rescue ArgumentError
      nil
    end
  end

  #
  # One installable entry from `app/list` (summary) or `app/get` (detail).
  #
  # `app/get` returns an `ApplicationDetail`: the summary fields below PLUS
  # `long_description`, `upstream_url`, `definition_url` and `releases`. The daemon marks the
  # detail fields `omitempty`, so an entry can legitimately arrive without them and every
  # caller must still treat them as optional -- the view falls back to placeholder text rather
  # than pretending the data exists.
  #
  # NOTE: the live catalog is not fully trustworthy - `version` is empty for some
  # entries, and `uri` may be a placeholder/relative path (e.g. "/tmp_redirect").
  # `available?` therefore does NOT consider `version`.
  #
  class CatalogEntry
    attr_reader :id, :name, :version, :redirect_uri, :description, :long_description,
                :upstream_url, :definition_url, :updated_at, :releases

    def initialize(id:, name:, version: nil, redirect_uri: nil, description: nil,
                   long_description: nil, upstream_url: nil, definition_url: nil,
                   updated_at: nil, releases: [])
      @id = id.to_s
      @name = name.to_s
      @version = version.presence
      @redirect_uri = redirect_uri.presence
      @description = description.presence
      @long_description = long_description.presence
      @upstream_url = upstream_url.presence
      @definition_url = definition_url.presence
      @updated_at = parse_time(updated_at)
      @releases = Array(releases).compact
    end

    def self.from_json(raw)
      return nil unless raw.is_a?(Hash)

      new(
        id: raw["id"],
        name: raw["name"],
        version: raw["version"],
        redirect_uri: raw["redirect_uri"],
        description: raw["description"],
        long_description: raw["long_description"],
        upstream_url: raw["upstream_url"],
        definition_url: raw["definition_url"],
        updated_at: raw["updated_at"],
        releases: Array(raw["releases"]).filter_map { |r| Release.from_json(r) }
      )
    end

    # True when the catalog told us something. Absent data is not an error: `app/get` omits
    # empty fields, and a list row never carries them at all.
    def described? = description.present?
    def long_described? = long_description.present?
    def updated? = updated_at.present?
    def upstream? = upstream_url.present?
    def definition_linked? = definition_url.present?
    def released_versions? = releases.any?

    #
    # True when the row carries enough information to be shown or installed. A row with
    # no id and no name is the zero-value entry a per-entry config.json failure used to
    # append (it swallowed that error), and must be dropped.
    #
    def available?
      id.present? && name.present?
    end

    # True when we know a concrete version. The live catalog leaves this blank for most
    # entries, so a blank version means "unknown", not "broken".
    def versioned? = version.present?

    def to_s = name.presence || id

    private

    # Accept an ISO8601 string or a Time; anything unparseable becomes nil so a bad
    # value degrades to "unknown" instead of raising inside a view.
    def parse_time(value)
      case value
      when nil then nil
      when Time, DateTime then value
      when String then Time.zone.parse(value)
      end
    rescue ArgumentError
      nil
    end
  end

  # Old name, kept so nothing breaks mid-refactor.
  Definition = CatalogEntry

  #
  # One installed app, from `inst/list`.
  #
  # The daemon returns `{instances: [{id, app, domain, version, status}, ...]}`. Every field
  # but `id` can still be empty: `version` is the catalog version rather than what is
  # running (there is no per-instance upgrade tracking yet), `domain` is read best-effort
  # from the app's env file and is blank for apps with no mapping, and `status` is blank
  # when docker compose cannot be reached. Blank means unknown, NOT "stopped" or
  # "unversioned" -- see AppStatusBadgeComponent.
  #
  class AppInstance
    attr_reader :id, :catalog_entry_id, :domain, :version, :status

    def initialize(id:, catalog_entry_id: nil, domain: nil, version: nil, status: nil)
      @id = id.to_s
      @catalog_entry_id = catalog_entry_id.presence
      @domain = domain.presence
      @version = version.presence
      @status = status.presence
    end

    def self.from_json(raw)
      return nil unless raw.is_a?(Hash)

      new(
        id: raw["id"],
        # dcommsctl calls this field "app" (and sometimes "name"); both mean the catalog
        # entry the app was created from.
        catalog_entry_id: raw["app"] || raw["name"],
        domain: raw["domain"],
        version: raw["version"],
        status: raw["status"]
      )
    end

    # Same guard as CatalogEntry#available? - drop rows without an identity.
    def available? = id.present?

    #
    # The two states the backend reports, asked as a question rather than compared as a string so
    # callers cannot drift on the spelling. Anything else -- including the blank status the daemon
    # sends when it cannot reach docker compose -- is neither: see AppStatusBadgeComponent, and
    # note that start/stop buttons are disabled in that third case rather than guessing.
    #
    def running? = status == "running"
    def stopped? = status == "stopped"
  end

  #
  # The result of `inst/install`.
  #
  # `job_id` identifies the async job; `id` is the new instance id. The OAuth
  # credentials are generated by the backend and handed to the app's installer, so
  # Dawa must register a matching Doorkeeper application.
  #
  class InstallResult
    attr_reader :job_id, :instance_id, :admin_login, :admin_pass,
                :client_id, :client_secret

    def initialize(job_id:, instance_id:, admin_login: nil, admin_pass: nil,
                   client_id: nil, client_secret: nil)
      @job_id = job_id.to_s
      @instance_id = instance_id.to_s
      @admin_login = admin_login.presence
      @admin_pass = admin_pass.presence
      @client_id = client_id.presence
      @client_secret = client_secret.presence
    end

    def self.from_json(raw)
      new(
        job_id: raw["job_id"],
        instance_id: raw["id"],
        admin_login: raw["admin_login"],
        admin_pass: raw["admin_pass"],
        client_id: raw["client_id"],
        client_secret: raw["client_secret"]
      )
    end

    #
    # True when the backend did not actually do anything.
    #
    # This is the anti-bug guard: `inst/install` has an empty `case` for unimplemented
    # apps (and a silent fallthrough for unknown names) that returns a zero-value
    # struct with NO error. Confirmed live: install with a bogus name returns six
    # empty-string fields. Without this check Dawa would report a successful install
    # of nothing and create a credential-less OAuth application.
    #
    def empty?
      [ job_id, instance_id, client_id, client_secret ].all?(&:blank?)
    end

    # True when we got credentials we can register for SSO.
    def credentials?
      client_id.present? && client_secret.present?
    end

    def to_s
      "InstallResult(job_id=#{job_id.inspect} instance_id=#{instance_id.inspect} " \
        "credentials=#{credentials?})"
    end
  end

  #
  # A job's state, from `job/status` / `job/list`.
  #
  # Timestamps arrive as RFC3339 strings (`jobs.go`'s JobStatus) and `finished_at` is EMPTY
  # while a job is still running, so `finished_at` is nil until the job ends. The raw strings
  # are kept as sent; `started_time` / `finished_time` are the parsed forms for display, and
  # both are nil when the daemon sent nothing or sent something unparseable.
  #
  class JobStatus
    STATES = %w[pending running done failed].freeze
    TERMINAL_STATES = %w[done failed].freeze

    attr_reader :id, :type, :instance_id, :state, :exit_code, :error,
                :bytes_written, :started_at, :finished_at

    def initialize(id:, state:, type: nil, instance_id: nil, exit_code: nil,
                   error: nil, bytes_written: nil, started_at: nil, finished_at: nil)
      @id = id.to_s
      @state = state.to_s
      @type = type.presence
      @instance_id = instance_id.presence
      @exit_code = exit_code
      @error = error.presence
      @bytes_written = bytes_written
      @started_at = started_at
      @finished_at = finished_at
    end

    def self.from_json(raw)
      new(
        id: raw["id"],
        state: raw["state"],
        type: raw["type"],
        instance_id: raw["instance_id"],
        exit_code: raw["exit_code"],
        error: raw["error"],
        bytes_written: raw["bytes_written"],
        started_at: raw["started_at"],
        finished_at: raw["finished_at"]
      )
    end

    # Only a job that reached a terminal state stops being polled.
    def terminal? = TERMINAL_STATES.include?(state)

    # Only `done` means success; `failed` carries an exit code and a message.
    def success? = state == "done"
    def failed? = state == "failed"
    def running? = !terminal?

    # Parsed `started_at`, or nil when absent/unparseable.
    def started_time = parse_time(started_at)

    # Parsed `finished_at`, or nil while the job is still running (the daemon sends "").
    def finished_time = parse_time(finished_at)

    # How long the job took, or nil while it is still running / for unparseable times.
    def duration
      first = started_time
      last = finished_time
      return nil if first.nil? || last.nil?

      last - first
    end

    private

    # Tolerate "" (not finished yet) and anything unparseable, so a bad timestamp degrades
    # to "unknown" in the view rather than raising inside a request.
    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end

  #
  # A chunk of job output, from `job/log`.
  #
  # `offset` is a byte cursor into the job's log; callers keep `next_offset` and pass it back
  # to fetch only new output. Note the daemon only serves a RUNNING job's log -- see
  # DcommsAdapter#job_log.
  #
  class JobLog
    attr_reader :log, :next_offset, :eof

    def initialize(log:, next_offset:, eof:)
      @log = log.to_s
      @next_offset = next_offset.to_i
      @eof = eof ? true : false
    end

    def self.from_json(raw)
      next_offset = raw["next_offset"] || raw["offset"] || 0
      new(log: raw["log"], next_offset: next_offset, eof: raw["eof"])
    end

    # No new output in this chunk.
    def empty? = log.empty?

    # NOTE: `eof` means "caught up for now", NOT "the job finished" -- completion is
    # only ever signalled by JobStatus#state.
    def to_s = "JobLog(bytes=#{log.bytesize} next_offset=#{next_offset} eof=#{eof})"
  end
end
