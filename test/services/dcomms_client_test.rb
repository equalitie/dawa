require "test_helper"
require "socket"

#
# Unit tests for the dcommsctl JSON-RPC client.
#
# Most of these stub `#exchange` (the socket round trip), so they run without a live
# daemon and pin the parts that actually encode the contract: request/response
# correlation, result unwrapping, error-code mapping, and the guards against the
# backend's silent no-op behaviours.
#
# The canned responses mirror what the live daemon was observed to return
# (see docs/dcommsctl-integration-plan.md, Step 0 / "Probe results").
#
# `#exchange` itself is covered by the transport tests at the bottom, which run the
# real WebSocket handshake against a loopback echo server.
#
class DcommsClientTest < ActiveSupport::TestCase
  setup do
    @client = DcommsClient.new(url: "ws://localhost:6006/ws")
    @sent = []
  end

  # Stub the transport: record the request we "sent", return a canned JSON-RPC response.
  #
  # NOTE: the block passed to define_singleton_method runs with `self` bound to the
  # client, so we must capture the recorder in a local (not an ivar on the test).
  def stub_exchange(result: :none, error: nil, &block)
    sent = @sent

    @client.define_singleton_method(:exchange) do |payload|
      sent << JSON.parse(payload)
      response = { "jsonrpc" => "2.0", "id" => sent.last["id"] }
      response["error"] = error if error
      response["result"] = result unless result == :none
      response
    end

    block.call
  ensure
    @client.singleton_class.send(:remove_method, :exchange)
  end

  ##
  ## request shape
  ##

  test "sends a JSON-RPC 2.0 request with a matching id" do
    stub_exchange(result: { "applications" => [] }) do
      @client.catalog_list
    end

    request = @sent.last
    assert_equal "2.0", request["jsonrpc"]
    assert_equal "app/list", request["method"]
    assert request["id"].present?, "request must carry an id"
  end

  test "omits params for parameterless methods" do
    stub_exchange(result: { "applications" => [] }) do
      @client.catalog_list
    end

    refute @sent.last.key?("params")
  end

  test "defaults the url to the configured dcomms_url" do
    assert_equal "ws://localhost:6006/ws", DcommsClient.new.url
    assert_equal "ws://other.test:6006/ws", DcommsClient.new(url: "ws://other.test:6006/ws").url
  end

  ##
  ## app/list
  ##

  test "catalog_list uses the singular app/list method" do
    # The daemon renamed this from apps/list; the plural form now returns -32601.
    # Confirmed against the live daemon (script/backend-ls).
    stub_exchange(result: { "applications" => [] }) do
      @client.catalog_list
    end

    assert_equal "app/list", @sent.last["method"]
  end

  test "catalog_list unwraps the applications array into Definition objects" do
    result = { "applications" => [
      { "id" => "peertube", "name" => "Peertube", "version" => "", "redirect_uri" => "/tmp_redirect" },
      { "id" => "dawa", "name" => "DAWA", "version" => "0.0.1", "redirect_uri" => "/tmp_redirect" }
    ] }

    stub_exchange(result: result) do
      definitions = @client.catalog_list
      assert_equal 2, definitions.size
      assert_equal "peertube", definitions.first.id
      assert_equal "Peertube", definitions.first.name
      # an empty version must NOT disqualify a definition (the live catalog has them)
      assert_nil definitions.first.version
      refute definitions.first.versioned?
      assert definitions.first.available?
    end
  end

  test "apps_list is a deprecated alias for catalog_list" do
    stub_exchange(result: { "applications" => [] }) do
      assert_equal @client.catalog_list, @client.apps_list
    end
  end

  test "catalog_list drops rows missing both id and name" do
    result = { "applications" => [
      { "id" => "peertube", "name" => "Peertube", "version" => "", "redirect_uri" => "/tmp_redirect" },
      { "id" => "", "name" => "", "version" => "", "redirect_uri" => "" }
    ] }

    stub_exchange(result: result) do
      assert_equal [ "peertube" ], @client.catalog_list.map(&:id)
    end
  end

  test "catalog_list parses the detail fields when the backend sends them" do
    # `apps/list` does not send these today, but the entry shape is shared with the detail
    # method, so the parser must handle them now rather than silently dropping them later.
    result = { "applications" => [ {
      "id" => "peertube", "name" => "Peertube", "version" => "7.0.0",
      "description" => "short", "long_description" => "much longer",
      "upstream_url" => "https://joinpeertube.org",
      "definition_url" => "https://example.test/defs/peertube",
      "updated_at" => "2026-03-04T10:00:00Z",
      "releases" => [ { "version" => "7.0.0", "released_at" => "2026-03-04T10:00:00Z" } ]
    } ] }

    stub_exchange(result: result) do
      entry = @client.catalog_list.first

      assert entry.long_described?
      assert_equal "https://joinpeertube.org", entry.upstream_url
      assert_equal "https://example.test/defs/peertube", entry.definition_url
      assert_equal 1, entry.releases.size
      assert_equal "7.0.0", entry.releases.first.version
      assert entry.releases.first.released?
    end
  end

  test "catalog_entry requests one entry by id and parses the detail" do
    result = {
      "id" => "peertube", "name" => "Peertube", "version" => "7.0.0",
      "long_description" => "much longer",
      "releases" => [
        { "version" => "7.0.0", "released_at" => "2026-03-04T10:00:00Z" },
        { "version" => "6.0.0" }
      ]
    }

    stub_exchange(result: result) do
      entry = @client.catalog_entry(id: "peertube")

      assert_equal "peertube", entry.id
      assert entry.long_described?
      assert_equal %w[7.0.0 6.0.0], entry.releases.map(&:version)
      refute entry.releases.last.released?, "a release with no date must not invent one"
    end

    assert_equal({ "id" => "peertube" }, @sent.last["params"])
    assert_equal "apps/get", @sent.last["method"]
  end

  test "catalog_entry drops releases with no version" do
    result = { "id" => "peertube", "name" => "Peertube",
               "releases" => [ { "version" => "7.0.0" }, { "version" => "" }, {} ] }

    stub_exchange(result: result) do
      assert_equal [ "7.0.0" ], @client.catalog_entry(id: "peertube").releases.map(&:version)
    end
  end

  test "catalog_entry raises EmptyResult for a blank entry" do
    # An all-empty response is the backend's way of saying nothing, which must not render
    # as a valid entry with no name.
    stub_exchange(result: { "id" => "", "name" => "" }) do
      assert_raises(DcommsClient::EmptyResult) { @client.catalog_entry(id: "nope") }
    end
  end

  ##
  ## error mapping
  ##

  test "maps -32601 to MethodNotFound" do
    error = { "code" => -32601, "message" => "method not found: job/status" }

    stub_exchange(error: error) do
      assert_raises(DcommsClient::MethodNotFound) { @client.job_status(id: "x") }
    end
  end

  test "maps -32602 to InvalidParams" do
    error = { "code" => -32602, "message" => "json: cannot unmarshal" }

    stub_exchange(error: error) do
      assert_raises(DcommsClient::InvalidParams) { @client.start(id: "x") }
    end
  end

  test "maps other codes to ServerError, carrying code and message" do
    error = { "code" => -32603, "message" => "boom" }

    stub_exchange(error: error) do
      e = assert_raises(DcommsClient::ServerError) { @client.uninstall(id: "x") }
      assert_equal(-32603, e.code)
      assert_equal "boom", e.rpc_message
    end
  end

  test "surfaces the job-lock condition as JobInProgress" do
    # The daemon returns every handler error as -32603 with the Go error text as the
    # message, so this is only distinguishable by its text.
    error = { "code" => -32603, "message" => "The job is in progress" }

    stub_exchange(error: error) do
      assert_raises(DcommsClient::JobInProgress) { @client.start(id: "peertube-quokka") }
    end
  end

  ##
  ## guards against silent no-ops
  ##

  test "install raises EmptyResult when the backend silently did nothing" do
    # Observed live for an unsupported app: six empty strings, no error.
    result = {
      "job_id" => "", "id" => "", "admin_login" => "", "admin_pass" => "",
      "client_id" => "", "client_secret" => ""
    }

    stub_exchange(result: result) do
      assert_raises(DcommsClient::EmptyResult) do
        @client.install(name: "definitely-not-an-app", domain: "example.test")
      end
    end
  end

  test "install returns credentials when the backend did real work" do
    result = {
      "job_id" => "install-09-12.10:00:00", "id" => "peertube-quokka",
      "admin_login" => "root", "admin_pass" => "test_pass",
      "client_id" => "cid", "client_secret" => "csecret"
    }

    stub_exchange(result: result) do
      install = @client.install(name: "peertube", domain: "peertube.test")
      refute install.empty?
      assert install.credentials?
      assert_equal "peertube-quokka", install.instance_id
      assert_equal "install-09-12.10:00:00", install.job_id
    end
  end

  test "mutations raise EmptyResult when no job id comes back" do
    stub_exchange(result: { "job_id" => "" }) do
      assert_raises(DcommsClient::EmptyResult) { @client.start(id: "x") }
    end
  end

  test "mutations return the job id" do
    stub_exchange(result: { "job_id" => "stop-09-12.10:00:00" }) do
      assert_equal "stop-09-12.10:00:00", @client.stop(id: "x")
    end
  end

  ##
  ## jobs
  ##

  test "job_status raises when the backend answers with a zero-value status" do
    # STILL A STUB: rpcJobStatus returns JobStatus{} and ignores the id, so a job that
    # job/list reports as `done` comes back all-empty. Observed live. A caller cannot tell
    # that apart from a genuinely pending job, so it is an error rather than a status.
    stub_exchange(result: { "id" => "", "state" => "" }) do
      assert_raises(DcommsClient::EmptyResult) { @client.job_status(id: "install-1") }
    end
  end

  test "job_status parses state and terminality" do
    result = {
      "id" => "install-1", "type" => "install", "instance_id" => "peertube-quokka",
      "state" => "failed", "exit_code" => 1, "error" => "compose failed",
      "bytes_written" => 2048, "started_at" => "2026-09-12T10:00:00Z"
    }

    stub_exchange(result: result) do
      status = @client.job_status(id: "install-1")
      assert status.terminal?
      assert status.failed?
      refute status.success?
      assert_equal 1, status.exit_code
      assert_equal 2048, status.bytes_written
    end

    assert_equal({ "id" => "install-1" }, @sent.last["params"])
  end

  test "job_status treats done as success and running as non-terminal" do
    stub_exchange(result: { "id" => "j", "state" => "done", "exit_code" => 0 }) do
      assert @client.job_status(id: "j").success?
    end

    stub_exchange(result: { "id" => "j", "state" => "running" }) do
      refute @client.job_status(id: "j").terminal?
    end
  end

  test "job_log sends the daemon's param names and both identifiers" do
    # The wire names are `job_id` and `instance_id` -- NOT the `id` every other method uses.
    # The daemon keys its job map on the pair, so `job_id` alone answers "Job not found".
    stub_exchange(result: { "log" => "line\n" }) do
      @client.job_log(id: "install-1", instance_id: "peertube-quokka")
    end

    assert_equal({ "job_id" => "install-1", "instance_id" => "peertube-quokka", "offset" => 0 },
                 @sent.last["params"])
  end

  test "job_log derives next_offset from the byte length of the chunk" do
    # The daemon replies with only `log`; the intended contract's `next_offset` is not sent,
    # so the client computes it: the offset asked from plus the bytes received. Safe because
    # the daemon reads from exactly that offset and a log is an opaque byte stream.
    stub_exchange(result: { "log" => "hello" }) do
      chunk = @client.job_log(id: "j", instance_id: "i", offset: 10)

      assert_equal "hello", chunk.log
      assert_equal 15, chunk.next_offset
    end
  end

  test "job_log measures the cursor in bytes, not characters" do
    # Multi-byte UTF-8 is the case a character count would get wrong, and the daemon's
    # offset is a byte offset (it uses ReadAt).
    text = "caf\u00e9\u00e9"

    stub_exchange(result: { "log" => text }) do
      chunk = @client.job_log(id: "j", instance_id: "i", offset: 0)

      assert_equal text.bytesize, chunk.next_offset
      assert_operator chunk.next_offset, :>, text.length
    end
  end

  test "an empty chunk means caught up" do
    # `eof` is not sent either. The daemon caps a reply at 64KB, so an empty chunk is the
    # only honest "nothing more right now". It is NOT completion -- that is job/status.
    stub_exchange(result: { "log" => "" }) do
      chunk = @client.job_log(id: "j", instance_id: "i", offset: 42)

      assert chunk.empty?
      assert chunk.eof
      assert_equal 42, chunk.next_offset, "an empty chunk must not move the cursor"
    end
  end

  test "a non-empty chunk is not eof" do
    stub_exchange(result: { "log" => "more\n" }) do
      refute @client.job_log(id: "j", instance_id: "i").eof
    end
  end

  test "job_list sends active_only only when asked" do
    stub_exchange(result: { "jobs" => [] }) { @client.job_list }
    refute @sent.last["params"].key?("active_only")

    stub_exchange(result: { "jobs" => [] }) { @client.job_list(active_only: true) }
    assert_equal true, @sent.last["params"]["active_only"]
  end

  test "job_list maps jobs and forwards the active_only filter" do
    result = { "jobs" => [ { "id" => "j1", "state" => "running" } ] }

    stub_exchange(result: result) do
      jobs = @client.job_list(active_only: true)
      assert_equal 1, jobs.size
      assert_equal "running", jobs.first.state
    end

    assert_equal({ "active_only" => true }, @sent.last["params"])
  end

  test "apps_installed_list reads the full rows the daemon now returns" do
    # `inst/list` returns {instances: [{id, app, domain, version, status}, ...]}
    # (InstancesListResult in rpc_inst_list.go). Regression guard: the client used to
    # collapse each row to its id and drop the rest, so status/version/domain arrived as
    # nil even though the daemon was sending them.
    result = {
      "instances" => [
        { "id" => "peertube-zebu", "app" => "peertube", "domain" => "pt.test",
          "version" => "7.0.0", "status" => "stopped" },
        { "id" => "dawa-okapi", "app" => "dawa", "domain" => "dawa.test",
          "version" => "0.0.1", "status" => "running" }
      ]
    }

    stub_exchange(result: result) do
      instances = @client.apps_installed_list

      assert_equal %w[peertube-zebu dawa-okapi], instances.map(&:id)

      stopped = instances.first
      assert_equal "stopped", stopped.status
      assert_equal "7.0.0", stopped.version
      assert_equal "pt.test", stopped.domain
      assert_equal "peertube", stopped.catalog_entry_id

      assert_equal "running", instances.last.status
      assert instances.last.running?
    end
  end

  test "apps_installed_list reports a blank status as unknown, not running" do
    # The daemon sends "" when it cannot ask docker compose. That must not read as running
    # (or as stopped); the view renders it as unknown.
    result = { "instances" => [ { "id" => "peertube-zebu", "status" => "" } ] }

    stub_exchange(result: result) do
      instance = @client.apps_installed_list.first

      assert_equal "peertube-zebu", instance.id
      assert_nil instance.status
      refute instance.running?, "an unknown status must not read as running"
    end
  end

  test "apps_installed_list still accepts the older bare-names shape" do
    # The daemon changed this method's shape once already. An older daemon sends
    # `InstancesNames: ["peertube-bongo", ...]`; that must degrade to id-only rows rather
    # than breaking the page.
    stub_exchange(result: { "InstancesNames" => [ "peertube-bongo", "peertube-zebu" ] }) do
      instances = @client.apps_installed_list

      assert_equal %w[peertube-bongo peertube-zebu], instances.map(&:id)
      assert_nil instances.first.status
      assert_nil instances.first.version
      assert_nil instances.first.domain
    end
  end

  test "apps_installed_list tolerates an empty or missing list" do
    stub_exchange(result: {}) do
      assert_equal [], @client.apps_installed_list
    end
  end

  test "apps_installed_list drops rows with no id" do
    # `available?` is the same guard the catalog uses: a row without an identity cannot be
    # rendered or linked to.
    result = { "instances" => [ { "id" => "" }, { "id" => "peertube-quokka" } ] }

    stub_exchange(result: result) do
      assert_equal [ "peertube-quokka" ], @client.apps_installed_list.map(&:id)
    end
  end

  ##
  ## protocol failures
  ##

  test "raises ProtocolError on malformed JSON" do
    assert_raises(DcommsClient::ProtocolError) { @client.send(:parse_response, "not json") }
  end

  test "raises ProtocolError when the response is not an object" do
    assert_raises(DcommsClient::ProtocolError) { @client.send(:parse_response, "[1,2,3]") }
  end

  test "raises ConnectionError when the url scheme is unsupported" do
    client = DcommsClient.new(url: "ftp://nope/ws")
    assert_raises(DcommsClient::ConnectionError) { client.send(:exchange, "{}") }
  end

  ##
  ## transport (real sockets)
  ##
  #
  # These drive the real handshake and frame parsing over loopback, so they catch
  # breakage in `#exchange`/`#read_reply` that stubbing cannot see. Regression guard
  # for the reply never being observed: the `:message` handler must hand its data
  # back to the read loop (a bare local rebound inside the handler is invisible to
  # the caller, which made every call time out despite a correct reply).

  test "completes a real websocket round trip and unwraps the result" do
    with_echo_server { |url| assert_client_round_trip(url) }
  end

  test "exchanges one request per call on a fresh connection" do
    requests = []

    with_echo_server(requests: requests) do |url|
      client = DcommsClient.new(url: url, timeout: 3)
      3.times { assert_equal [], client.catalog_list }
    end

    assert_equal 3, requests.size, "each call must open its own connection"
    assert_equal %w[app/list app/list app/list], requests.map { |r| r["method"] }
  end

  test "raises ConnectionError when nothing is listening" do
    # Bind and immediately release a port so we have one that is almost certainly free.
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close

    client = DcommsClient.new(url: "ws://127.0.0.1:#{port}/ws", timeout: 1)

    assert_raises(DcommsClient::ConnectionError) { client.catalog_list }
  end

  #
  # A minimal WebSocket echo server: does the handshake, and answers each JSON-RPC
  # request with `result: {applications: []}`.
  #
  # Accepts connections until the server socket is closed by `with_echo_server`, so
  # it can serve tests that make several calls (the client opens one per call).
  #
  # @param requests [Array<Hash>, nil] collects the decoded requests the server saw.
  #
  def with_echo_server(requests: nil)
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new { serve_echo_connections(server, requests) }

    yield "ws://127.0.0.1:#{port}/ws"
  ensure
    server&.close
    thread&.join(2)
  end

  def serve_echo_connections(server, requests)
    loop { serve_echo_connection(server.accept, requests) }
  rescue IOError, SystemCallError
    # server closed by with_echo_server; no more connections to serve
  end

  def serve_echo_connection(socket, requests)
    driver = WebSocket::Driver.server(socket)
    driver.on(:connect) { driver.start }
    driver.on(:message) { |event| reply_to(socket, driver, event.data, requests) }

    loop do
      begin
        driver.parse(socket.read_nonblock(DcommsClient::READ_CHUNK))
      rescue IO::WaitReadable
        IO.select([ socket ], nil, nil, 0.1)
      rescue EOFError, IOError, SystemCallError
        break # client closed after reading its reply
      end
    end
  end

  def reply_to(socket, driver, data, requests)
    request = JSON.parse(data)
    requests << request if requests

    driver.text(JSON.generate({ "jsonrpc" => "2.0", "id" => request["id"],
                                "result" => { "applications" => [] } }))
  rescue IOError, SystemCallError
    socket.close
  end

  def assert_client_round_trip(url)
    assert_equal [], DcommsClient.new(url: url, timeout: 3).catalog_list
  end
end
