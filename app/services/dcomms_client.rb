require "websocket/driver"
require "socket"
require "uri"
require "json"
require "securerandom"

#
# JSON-RPC 2.0 client for the dcommsctl backend (a Go daemon that installs and
# supervises docker-compose applications for Dawa).
#
# Transport: **one WebSocket connection per call** — open, send one request, read the
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
#   DcommsClient.new.apps_list
#   # => [ #<Dcomms::App id="peertube" name="Peertube" ...>, ... ]
#
# NOTE: the backend does not yet implement `job/status`, `job/log` (real output) or
# `inst/list`; see docs/dcommsctl-api-requests.md. DcommsAdapter is what decides
# whether to call this class or the mock.
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
  # --- Catalog -----------------------------------------------------------
  #

  # `apps/list` — the catalog of installable applications.
  #
  # @return [Array<Dcomms::App>] only rows with an id and name (see App#available?).
  #
  def apps_list
    result = call("apps/list")
    applications = result.is_a?(Hash) ? result["applications"] : result
    Array(applications).filter_map { |raw| Dcomms::App.from_json(raw) }.select(&:available?)
  end

  #
  # --- Instances ---------------------------------------------------------
  #

  # `inst/list` — installed instances. NOT IMPLEMENTED by the backend yet
  # (raises MethodNotFound); DcommsAdapter mocks it.
  #
  # @return [Array<Dcomms::Instance>]
  #
  def instances_list
    result = call("inst/list")
    instances = result.is_a?(Hash) ? result["instances"] : result
    Array(instances).filter_map { |raw| Dcomms::Instance.from_json(raw) }.select(&:available?)
  end

  # `inst/install` — install an app. Starts a job; returns its id plus the OAuth
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
  # --- Jobs --------------------------------------------------------------
  #

  # `job/status` — NOT IMPLEMENTED yet (raises MethodNotFound). DcommsAdapter mocks it.
  #
  # @return [Dcomms::JobStatus]
  #
  def job_status(id:)
    Dcomms::JobStatus.from_json(call("job/status", { id: id }))
  end

  # `job/log` — registered but stubbed by the backend (always returns an empty log).
  #
  # @return [Dcomms::JobLog]
  #
  def job_log(id:, offset: 0)
    Dcomms::JobLog.from_json(call("job/log", { id: id, offset: offset }))
  end

  # `job/list` — NOT IMPLEMENTED yet. DcommsAdapter mocks it.
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

    reply = nil
    protocol_error = nil

    driver.on(:message) { |event| reply ||= event.data }
    driver.on(:error) { |event| protocol_error ||= event.message }
    driver.on(:open) { driver.text(payload) }

    begin
      driver.start
      reply = read_reply(socket, driver, reply, protocol_error)
    ensure
      close_socket(socket)
    end

    raise ProtocolError, "dcommsctl WebSocket error: #{protocol_error}" if protocol_error
    raise ProtocolError, "dcommsctl closed the connection without replying" if reply.nil? || reply.empty?

    parse_response(reply)
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
  def read_reply(socket, driver, reply, protocol_error)
    deadline = monotonic + @timeout

    while reply.nil? && protocol_error.nil?
      raise ConnectionError, "dcommsctl did not reply within #{@timeout}s" if monotonic > deadline

      begin
        driver.parse(socket.read_nonblock(READ_CHUNK))
      rescue IO::WaitReadable
        IO.select([ socket ], nil, nil, 0.2)
      rescue EOFError
        break
      end
    end

    reply
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
