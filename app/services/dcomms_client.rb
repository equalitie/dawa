require "websocket/driver"
require "socket"
require "uri"
require "json"
require "securerandom"

#
# JSON-RPC 2.0 client for the dcommsctl backend (a Go daemon that installs and
# supervises docker-compose applications for Dawa).
#
# Transport: **one WebSocket connection per call** -- open, send one request, read the
# reply, close. dcommsctl speaks JSON-RPC over `ws://host:6006/ws`.
#
# Deliberately stateless. Every long-running call is made from a background job (not
# from a web request), so there is nothing to keep a socket alive for; a per-call
# connection avoids a reader thread and an id→reply correlation map entirely.
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

  # `inst/uninstall`
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
  # STILL A STUB in the daemon: `rpcJobStatus` returns a zero-value JobStatus and never
  # looks at the id, so this answers `ok` with every field blank for a job that `job/list`
  # reports as `done`. DcommsAdapter therefore keeps it mocked.
  #
  # It raises on a blank id rather than handing back a zero-value status, because a caller
  # cannot tell "this job is pending" from "the backend did not answer" otherwise, and the
  # second is what is actually happening. That check becomes harmless once the daemon
  # implements the method properly.
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
  # The daemon keys its job map on instance+job (`fetchLog(instanceID, jobID, offset)`), so
  # BOTH identifiers are required; `job_id` alone gets "Job not found". The wire names are
  # `job_id` and `instance_id` -- not `id`, which is the name every other method uses.
  #
  # The reply carries only `log`. The intended contract also has `next_offset` and `eof`,
  # which the daemon does not send, so they are derived here:
  #
  #   * `next_offset` is the byte cursor the client should pass next: the offset it asked
  #     from, plus the bytes it just received. Deriving it (rather than trusting the daemon
  #     to echo it) is safe because the daemon reads from exactly that offset and the log is
  #     an opaque byte stream.
  #   * `eof` means "caught up for now". The daemon caps a reply at 64KB, so an EMPTY chunk
  #     is the only honest signal that there is nothing more to read. That is a guess in the
  #     strict sense -- a genuinely empty reply and a short read look alike -- but the
  #     alternative (always reporting eof: false) would make every caller poll forever.
  #
  # Completion is NEVER signalled here regardless: that is `job/status#state`.
  #
  # @param id [String] the job id
  # @param instance_id [String] the instance the job belongs to
  # @param offset [Integer] byte offset to read from
  # @return [Dcomms::JobLog]
  #
  def job_log(id:, instance_id:, offset: 0)
    raw = call("job/log", { job_id: id, instance_id: instance_id, offset: offset.to_i })
    text = raw.is_a?(Hash) ? raw["log"].to_s : ""

    Dcomms::JobLog.new(log: text, next_offset: offset.to_i + text.bytesize, eof: text.empty?)
  end

  # `job/list` -- NOT IMPLEMENTED yet. DcommsAdapter mocks it.
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
  # Perform one JSON-RPC exchange on a fresh connection.
  #
  # @return [Object] the `result` payload (Hash, Array, ...), or nil when absent.
  #
  def call(method, params = nil)
    request_id = SecureRandom.hex(4)

    response = exchange(
      JSON.generate({ jsonrpc: "2.0", method: method, params: params }.compact.merge(id: request_id))
    )

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

  # Open a socket, write the request, read exactly one message, close.
  def exchange(payload)
    uri = URI.parse(@url)
    raise ConnectionError, "unsupported dcommsctl URL: #{@url.inspect}" unless uri.is_a?(URI::WS) || uri.is_a?(URI::HTTP)

    socket = open_socket(uri)
    driver = WebSocket::Driver.client(SocketDelegate.new(socket, @url))

    # A shared mutable box, not a bare local: the :message handler is called from
    # inside read_reply, and rebinding a local of *this* method there would be
    # invisible to the read loop (Ruby passes values, not references).
    reply = []
    protocol_error = nil

    driver.on(:message) { |event| reply << event.data }
    driver.on(:error) { |event| protocol_error ||= event.message }
    driver.on(:open) { driver.text(payload) }

    begin
      driver.start
      read_reply(socket, driver, reply, protocol_error)
    ensure
      close_socket(socket)
    end

    raise ProtocolError, "dcommsctl WebSocket error: #{protocol_error}" if protocol_error

    message = reply.first
    raise ProtocolError, "dcommsctl closed the connection without replying" if message.nil? || message.empty?

    parse_response(message)
  end

  def open_socket(uri)
    TCPSocket.new(uri.host, uri.port || default_port(uri))
  rescue SystemCallError, SocketError => e
    raise ConnectionError, "could not reach dcommsctl at #{@url}: #{e.message}"
  end

  def default_port(uri)
    uri.scheme == "wss" ? 443 : 80
  end

  # Pump the socket until a message arrives or we exceed the timeout.
  #
  # `reply` is a mutable box shared with the :message handler, so it is read as
  # `reply.empty?` rather than being assigned here.
  def read_reply(socket, driver, reply, protocol_error)
    deadline = monotonic + @timeout

    while reply.empty? && protocol_error.nil?
      raise ConnectionError, "dcommsctl did not reply within #{@timeout}s" if monotonic > deadline

      begin
        driver.parse(socket.read_nonblock(READ_CHUNK))
      rescue IO::WaitReadable
        IO.select([ socket ], nil, nil, 0.2)
      rescue EOFError
        break
      end
    end
  end

  def close_socket(socket)
    socket.close
  rescue IOError, SystemCallError
    # already closed by the peer; nothing to do
  end

  def parse_response(raw)
    parsed = JSON.parse(raw)
    raise ProtocolError, "dcommsctl sent a non-object response: #{raw[0, 120]}" unless parsed.is_a?(Hash)

    parsed
  rescue JSON::ParserError => e
    raise ProtocolError, "dcommsctl sent malformed JSON: #{e.message}"
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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
