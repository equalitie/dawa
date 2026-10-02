require "websocket/driver"
require "socket"
require "uri"
require "json"
require "securerandom"

#
# JSON-RPC 2.0 client for the dcommsctl backend (a Go daemon that installs and
# supervises docker-compose applications for Dawa).
#
# Transport: **one WebSocket connection, reused across calls**. The socket is opened lazily on the
# first call and kept until something closes it, at which point the next call opens a fresh one and
# retries once. dcommsctl speaks JSON-RPC over `ws://host:6006/ws`.
#
# Why reused rather than per-call: following a job polled `job/status` and `job/log` on a timer,
# and every poll paid a TCP connect plus a WebSocket handshake twice over -- which is what made a
# fast poll interval expensive. Reusing the socket makes each poll a couple of frames.
#
# This is still request/response, NOT streaming. The client sends one request and waits for its
# reply before returning, so there is no reader thread and no id-to-reply correlation map: exactly
# one request is ever in flight. That keeps the robustness of polling -- a dropped connection is
# recoverable, because the caller's state (the log offset) lives outside the socket -- while
# removing the per-call cost.
#
# Not thread-safe, deliberately. Each caller builds its own client; a shared one would need the
# in-flight guarantee above to be enforced rather than assumed.
#
# It wraps `websocket-driver`, which is already present via ActionCable, so no new gem
# is required.
#
# Example:
#   DcommsClient.new.catalog_list
#   # => [ #<Dcomms::CatalogEntry id="peertube" name="Peertube" ...>, ... ]
#
class DcommsClient
  # Base for every failure raised by this client.
  class Error < StandardError; end

  # The socket could not be opened, or died mid-exchange ("unreachable").
  class ConnectionError < Error; end

  # The reply was not valid JSON or not a well-formed JSON-RPC response.
  class ProtocolError < Error; end

  # The backend answered with a JSON-RPC error object.
  class RPCError < Error
    attr_reader :code, :rpc_message

    def initialize(code:, message:)
      @code = code
      @rpc_message = message
      super("dcommsctl error #{code}: #{message}")
    end
  end

  # The requested method is not registered on the backend (JSON-RPC -32601).
  class MethodNotFound < RPCError; end

  # The backend rejected our params (JSON-RPC -32602).
  class InvalidParams < RPCError; end

  # The backend reported an internal failure (JSON-RPC -32603, or any other code).
  class ServerError < RPCError; end

  # A recognized "try again later" error, surfaced as its own class so the UI can
  # explain it. dcommsctl returns this as a plain error string when another job holds
  # the instance lock ("The job is in progress"), which currently arrives as -32603.
  class JobInProgress < ServerError; end

  # A mutation reported success but did nothing (see Dcomms::InstallResult#empty?).
  class EmptyResult < Error; end

  JSONRPC_METHOD_NOT_FOUND = -32601
  JSONRPC_INVALID_PARAMS = -32602
  JSONRPC_INTERNAL_ERROR = -32603

  # Message the daemon returns when an instance's job lock is already held.
  JOB_IN_PROGRESS_MESSAGE = "The job is in progress"

  DEFAULT_OPEN_TIMEOUT = 2
  DEFAULT_TIMEOUT = 10
  READ_CHUNK = 4096

  def initialize(url: nil, open_timeout: nil, timeout: nil)
    @url = url || Conf.dcomms_url
    @open_timeout = (open_timeout || Conf.dcomms_timeout || DEFAULT_OPEN_TIMEOUT).to_f
    @timeout = (timeout || Conf.dcomms_timeout || DEFAULT_TIMEOUT).to_f
  end

  # The WebSocket URL this client talks to (useful for diagnostics/banners).
  attr_reader :url

  #
  #
  ##
  ## Catalog
  ##
  #

  #
  # `app/list` - the catalog of installable entries.
  #
  # SINGULAR `app`, not `apps`: the method was renamed (confirmed live), and the old
  # `apps/list` now returns -32601. See docs/dcommsctl-api-requests.md.
  #
  # dcommsctl calls this method "app" and returns "applications", but what it returns is
  # what CAN be installed, not what IS. In Dawa those are catalog entries, and "app" is
  # reserved for an installed deployment (see the vocabulary note in dcomms.rb).
  #
  # @return [Array<Dcomms::CatalogEntry>] only rows with an id and name.
  #
  def catalog_list
    result = call("app/list")
    applications = result.is_a?(Hash) ? result["applications"] : result
    Array(applications).filter_map { |raw| Dcomms::CatalogEntry.from_json(raw) }.select(&:available?)
  end

  # Old names, kept so nothing breaks mid-refactor.
  alias_method :definitions_list, :catalog_list
  alias_method :apps_list, :catalog_list

  #
  # `app/get` - one catalog entry, with the detail `app/list` omits.
  #
  # SINGULAR `app`, like `app/list`: the daemon registers `app/get` and nothing else. The
  # method was added in rpc_app_get.go and returns an `ApplicationDetail` (the summary fields
  # plus long_description, upstream_url, definition_url and releases).
  #
  # An unknown id is an error, not an empty entry: the handler rejects ids outside the
  # `appIDs` allowlist before touching the filesystem.
  #
  # @return [Dcomms::CatalogEntry]
  #
  def catalog_entry(id:)
    entry = Dcomms::CatalogEntry.from_json(call("app/get", { id: id }))
    raise EmptyResult, "dcommsctl returned no catalog entry for #{id.inspect}" if entry.nil? || !entry.available?

    entry
  end

  #
  ##
  ## Apps (installed)
  ##
  #

  #
  # `inst/list` - the installed instances.
  #
  # The daemon returns `{ "instances": [{id, app, domain, version, status}, ...] }`
  # (`InstancesListResult` in rpc_inst_list.go). An earlier version returned
  # `InstancesNames: ["peertube-bongo", ...]` -- bare directory names with no other fields
  # -- and `instances_from` still tolerates that shape so a daemon rollback degrades rather
  # than breaking the page.
  #
  # Note the key casing: the current result key is lowercase `instances`, while the old
  # bare-names key was `InstancesNames` (Go field name, empty json tag).
  #
  # Every field is still optional from the caller's point of view. `status` is empty when
  # the daemon cannot reach docker compose, which means UNKNOWN rather than "stopped"
  # (see AppStatusBadgeComponent).
  #
  # @return [Array<Dcomms::AppInstance>]
  #
  def apps_installed_list
    result = call("inst/list")

    instances_from(result).filter_map { |raw| Dcomms::AppInstance.from_json(raw) }.select(&:available?)
  end

  # Old name, kept so nothing breaks mid-refactor.
  alias_method :instances_list, :apps_installed_list

  # `inst/install` -- install an app. Starts a job; returns its id plus the OAuth
  # credentials the backend generated for the new instance.
  #
  # @raise [EmptyResult] when the backend silently did nothing (unimplemented app).
  #
  def install(name:, domain:)
    result = call("inst/install", { name: name, domain: domain })
    install_result = Dcomms::InstallResult.from_json(result)

    raise EmptyResult, "dcommsctl reported no work for app #{name.inspect}" if install_result.empty?

    install_result
  end

  #
  # `inst/uninstall` -- tear down an app instance.
  #
  # An ASYNC job like the other mutations: the daemon returns a job id and runs
  # `docker compose down` under the instance's lock. The conflicting name is resolved there --
  # a second job for the same instance is refused with "The job is in progress", which
  # surfaces as `JobInProgress`.
  #
  # NOTE: this only stops and removes the app's containers. The daemon does not delete the
  # instance's data, so the deployed volumes remain on disk, and Dawa must not claim otherwise
  # (see the scope note on apps/uninstall.html.haml).
  #
  # @return [String] dcommsctl's job id
  # @raise [EmptyResult] when the backend returned no job id at all
  #
  def uninstall(id:) = job_id_from(call("inst/uninstall", { id: id }), "inst/uninstall")

  # `inst/start`
  def start(id:) = job_id_from(call("inst/start", { id: id }), "inst/start")

  # `inst/stop`
  def stop(id:) = job_id_from(call("inst/stop", { id: id }), "inst/stop")

  # `inst/backup`
  def backup(id:) = job_id_from(call("inst/backup", { id: id }), "inst/backup")

  # `inst/restore`
  def restore(id:) = job_id_from(call("inst/restore", { id: id }), "inst/restore")

  #
  ##
  ## Jobs
  ##
  #

  #
  # `job/status` - a job's state.
  #
  # Real: the daemon implements `statusByID`. It raises for an unknown job rather than
  # inventing a state, so a caller can tell "no such job" from "the backend did not answer".
  #
  # @return [Dcomms::JobStatus]
  #
  def job_status(id:)
    status = Dcomms::JobStatus.from_json(call("job/status", { id: id }))

    if status.id.blank?
      raise EmptyResult, "dcommsctl returned an empty job status for #{id.inspect}"
    end

    status
  end

  #
  # `job/log` - a chunk of a job's output.
  #
  # Takes ONLY the job id. The daemon looks the instance up itself (`instanceIDForJob`) and rejects
  # an id it does not know, so the wire name is `id` -- NOT `job_id`, and there is no
  # `instance_id`. Sending the older pair leaves `id` empty on the wire, which the daemon reports
  # as `unknown job:` with a blank id.
  #
  # The reply carries `log`, `next_offset` and `done`:
  #
  #   * `next_offset` is the cursor to pass next. The daemon hands it back rather than the caller
  #     counting bytes, so a multi-byte chunk cannot put the two out of step.
  #   * `done` is the daemon saying the LOG IS FINISHED: the job has ended and this reply reached
  #     the end of its output, so nothing more will ever be appended. A job that is still running
  #     answers with `done: false` even when the chunk is empty, which is what makes completion a
  #     fact instead of a guess -- an empty chunk alone cannot be told apart from a quiet job.
  #     See Dcomms::JobLog#finished.
  #
  # A cursor at or past the end of a log is not an error: the daemon answers with an empty chunk,
  # so a caller that has read everything can ask again without handling a failure.
  #
  # @param id [String] the job id, as returned by `inst/install` or listed by `job/list`
  # @param offset [Integer] byte offset to read from
  # @return [Dcomms::JobLog]
  #
  def job_log(id:, offset: 0)
    offset = offset.to_i
    raw = call("job/log", { id: id, offset: offset })
    raw = {} unless raw.is_a?(Hash)

    text = raw["log"].to_s

    Dcomms::JobLog.new(
      log: text,
      # The daemon's cursor. Deriving it is only a fallback for a daemon older than the field:
      # the cursor is just bytes read, so counting them is safe, whereas reusing a stale offset
      # would replay output the caller already has.
      next_offset: raw["next_offset"] || offset + text.bytesize,
      # An absent flag means "not finished", never "finished": a caller that stops reading early
      # loses the tail of a failed job's output, which is the part a log is read for.
      finished: raw["done"] == true
    )
  end

  # `job/list` - the jobs the daemon knows about.
  #
  # Real, and filterable by instance server-side. Jobs are persisted to `.jobs_db.json` and
  # reloaded on daemon startup, so this reports finished work as well as live work.
  #
  # @return [Array<Dcomms::JobStatus>]
  #
  def job_list(instance_id: nil, active_only: false)
    params = {}
    params[:instance_id] = instance_id if instance_id
    params[:active_only] = true if active_only

    result = call("job/list", params)
    jobs = result.is_a?(Hash) ? result["jobs"] : result
    Array(jobs).map { |raw| Dcomms::JobStatus.from_json(raw) }
  end

  private

  #
  #
  # The installed instances from an `inst/list` reply, as raw hashes ready for
  # `Dcomms::AppInstance.from_json`.
  #
  #
  # The installed instances from an `inst/list` reply, as raw hashes ready for
  # `Dcomms::AppInstance.from_json`.
  #
  # Two shapes are accepted:
  #
  #   * `{ "instances": [{id, app, domain, version, status}, ...] }` -- current.
  #   * `{ "InstancesNames": ["peertube-bongo", ...] }` -- the older bare-names shape.
  #
  # Keeping the old branch is deliberate: the daemon has changed this method's shape once
  # already, and degrading to "id only" is better than the page breaking outright. A bare
  # string is wrapped as `{"id" => name}` so both branches produce one shape downstream.
  #
  # @return [Array<Hash>] raw instance hashes.
  #
  def instances_from(result)
    entries = case result
    when Array then result
    when Hash then Array(result["instances"] || result["InstancesNames"])
    else []
    end

    entries.filter_map do |entry|
      case entry
      when Hash then entry
      when String then { "id" => entry }
      end
    end
  end

  # Extract a job_id from a mutation result, guarding against an empty answer.
  def job_id_from(result, method)
    job_id = result.is_a?(Hash) ? result["job_id"].to_s : ""
    raise EmptyResult, "dcommsctl #{method} returned no job id" if job_id.blank?

    job_id
  end

  #
  # Perform one JSON-RPC exchange.
  #
  # @return [Object] the `result` payload (Hash, Array, ...), or nil when absent.
  #
  def call(method, params = nil)
    request_id = SecureRandom.hex(4)

    response = exchange(
      JSON.generate({ jsonrpc: "2.0", method: method, params: params }.compact.merge(id: request_id))
    )

    Log.api("<-", response.inspect)

    if response.key?("error")
      raise_error_for(response["error"])
    end

    response["result"]
  end

  # Map a JSON-RPC error object onto a typed exception.
  #
  # dcommsctl returns *all* handler errors as -32603 with the Go error text as the
  # message, so "the job is in progress" is only distinguishable by its message. That
  # is why JobInProgress is matched on text.
  def raise_error_for(error)
    code = error["code"]
    message = error["message"].to_s

    raise JobInProgress.new(code: code, message: message) if message.include?(JOB_IN_PROGRESS_MESSAGE)

    case code
    when JSONRPC_METHOD_NOT_FOUND
      raise MethodNotFound.new(code: code, message: message)
    when JSONRPC_INVALID_PARAMS
      raise InvalidParams.new(code: code, message: message)
    else
      raise ServerError.new(code: code, message: message)
    end
  end

  # Send one request and return its response, over the held connection.
  #
  # Retries ONCE on a connection that turns out to be dead. That single retry is the whole
  # robustness story: it distinguishes "the socket died since the last call" (expected -- the daemon
  # restarted, or an idle connection was reaped) from "the daemon is not answering" (which surfaces
  # as ConnectionError). Only the first is worth retrying, and retrying more than once would turn a
  # daemon that is down into a slow failure.
  def exchange(payload)
    attempts = 0

    begin
      attempts += 1
      connection.exchange(payload)
    rescue ConnectionError => e
      # Retry only what is worth retrying. A stale socket leaving the connection dead IS worth
      # retrying; a daemon we could not reach at all is not -- there was never a connection to
      # blame, and retrying would just make an unreachable daemon fail slowly. `opened?` is the
      # discriminator because the failure path closes the connection before we see the error,
      # which makes `established?` uselessly false in both cases.
      raise if attempts > 1 || !connection.opened?

      close_connection
      retry
    end
  end

  # The held connection, opened on first use.
  def connection
    @connection ||= Connection.new(@url, @timeout)
  end

  # Drop the held connection so the next call opens a fresh one.
  def close_connection
    @connection&.close
    @connection = nil
  end

  def parse_response(raw)
    parsed = JSON.parse(raw)
    raise ProtocolError, "dcommsctl sent a non-object response: #{raw[0, 120]}" unless parsed.is_a?(Hash)

    parsed
  rescue JSON::ParserError => e
    raise ProtocolError, "dcommsctl sent malformed JSON: #{e.message}"
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  #
  # One WebSocket connection to the daemon, reused across calls.
  #
  # Opened lazily by the first `exchange`, and left open until it fails or `close` is called.
  # Each exchange sends one request and blocks for its reply, so at most one request is in flight
  # and replies cannot be confused with each other -- which is why there is no id correlation here
  # even though the connection outlives a single call.
  #
  # A dead connection is DETECTED, not prevented: the peer may have closed it while idle, and the
  # only reliable moment to find out is on the next write or read. Both are treated as
  # `ConnectionError`, and the client retries once on a fresh socket.
  #
  class Connection
    def initialize(url, timeout)
      @url = url
      @timeout = timeout
      @opened = false
    end

    # True once a socket has been open and not known to be dead.
    def established? = !@socket.nil?

    # True once this connection ever got a socket open. Unlike `established?` this survives a
    # failure: on any transport error the connection closes itself, so by the time the error
    # reaches the caller `established?` is always false. This says "there was a real socket to
    # blame", which is the question the retry decision actually needs answered.
    def opened? = !!@opened

    # Send a request and return the parsed response.
    def exchange(payload)
      connect unless established?

      # Clear the reply slot BEFORE sending. The connection is reused, so without this the FIRST
      # reply ever received stays at the head of `@reply` and every later exchange returns it: the
      # cursor never advances, so a log follower re-broadcasts the same chunk forever. `read_response`
      # cannot tell a stale reply from a fresh one, because the client deliberately does not correlate
      # replies with request ids (one request is in flight at a time).
      @reply = []
      @protocol_error = nil

      write(payload)
      read_response
    rescue ConnectionError
      # Any transport failure invalidates the connection, so the next call opens a new one rather
      # than retrying a socket we already know is broken.
      close
      raise
    end

    def close
      @socket&.close
    rescue IOError, SystemCallError
      # already closed by the peer; nothing to do
    ensure
      @socket = nil
      @driver = nil
    end

    private

    def connect
      uri = URI.parse(@url)
      unless uri.is_a?(URI::WS) || uri.is_a?(URI::HTTP)
        raise ConnectionError, "unsupported dcommsctl URL: #{@url.inspect}"
      end

      # A socket is a stated fact as soon as it is opened, so `@opened` is set before the handshake
      # rather than after it. The handshake is exactly where a peer that closed an idle connection
      # is discovered, and the client decides whether to retry by asking whether a socket was ever
      # opened. Setting the flag only on a successful handshake made a dropped idle connection
      # indistinguishable from an unreachable daemon, which lost the request instead of retrying.
      socket = TCPSocket.new(uri.host, uri.port || default_port(uri))
      @socket = socket
      @opened = true

      begin
        handshake(socket)
      rescue ConnectionError
        close
        raise
      end
    rescue SystemCallError, SocketError => e
      close
      raise ConnectionError, "could not reach dcommsctl at #{@url}: #{e.message}"
    end

    def handshake(socket)
      @driver = WebSocket::Driver.client(SocketDelegate.new(socket, @url))

      # A shared mutable box, not a bare local: the :message handler is called from inside the read
      # loop, and rebinding a local there would be invisible to it (Ruby passes values, not
      # references). Reset per exchange, not just here -- see `exchange`.
      @reply = []
      @protocol_error = nil

      @driver.on(:message) { |event| @reply << event.data }
      @driver.on(:error) { |event| @protocol_error ||= event.message }

      @driver.start
      await_open
    end

    # Wait for the handshake to complete before the first request goes out.
    #
    # Sending before `:open` would be a protocol violation, and `websocket-driver` does not queue
    # frames written early -- so this waits, and a daemon that accepts the TCP connection but never
    # completes the handshake fails here rather than hanging on a request that was never sent.
    def await_open
      deadline = monotonic + @timeout

      until @driver.state == :open
        if monotonic > deadline
          raise ConnectionError, "dcommsctl did not complete its handshake within #{@timeout}s"
        end

        # pump returns false at EOF, which during a handshake means the peer closed on us.
        raise ConnectionError, "dcommsctl closed the connection during its handshake" unless pump
      end
    end

    def write(payload)
      Log.api("->", payload)
      @driver.text(payload)
    rescue IOError, SystemCallError => e
      raise ConnectionError, "dcommsctl connection failed while sending: #{e.message}"
    end

    def read_response
      deadline = monotonic + @timeout

      while @reply.empty? && @protocol_error.nil?
        if monotonic > deadline
          raise ConnectionError, "dcommsctl did not reply within #{@timeout}s"
        end

        break unless pump
      end

      raise ProtocolError, "dcommsctl WebSocket error: #{@protocol_error}" if @protocol_error

      # `first`, not `shift`: `exchange` resets `@reply` before every send, so this reply cannot be
      # read a second time. Resetting in one place is what makes the reuse correct; consuming here as
      # well would be a second mechanism guarding the same invariant, and the two could drift.
      message = @reply.first
      if message.nil? || message.empty?
        # EOF mid-exchange. The daemon closed the connection, or died.
        raise ConnectionError, "dcommsctl closed the connection without replying"
      end

      parse_response(message)
    end

    # Read whatever is available and feed it to the driver.
    #
    # Returns false at EOF, which is how a closed peer is noticed. Sockets are read with
    # read_nonblock + select rather than blocking reads so the timeout above is enforced: a peer
    # that accepts the connection and then goes silent would otherwise block here indefinitely.
    def pump
      @driver.parse(@socket.read_nonblock(DcommsClient::READ_CHUNK))
      true
    rescue IO::WaitReadable
      IO.select([ @socket ], nil, nil, 0.2)
      true
    rescue EOFError
      false
    rescue IOError, SystemCallError => e
      raise ConnectionError, "dcommsctl connection failed while reading: #{e.message}"
    end

    def default_port(uri)
      uri.scheme == "wss" ? 443 : 80
    end

    def parse_response(raw)
      parsed = JSON.parse(raw)
      raise ProtocolError, "dcommsctl sent a non-object response: #{raw[0, 120]}" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => e
      raise ProtocolError, "dcommsctl sent malformed JSON: #{e.message}"
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # `websocket-driver`'s client calls `write` on its delegate and reads its `url`.
  # A TCPSocket supplies the former; we carry the latter.
  class SocketDelegate
    def initialize(socket, url)
      @socket = socket
      @url = url
    end

    attr_reader :url

    def write(data)
      @socket.write(data)
    end
  end
end
