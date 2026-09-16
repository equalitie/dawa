require "test_helper"

#
# Unit tests for the dcommsctl JSON-RPC client.
#
# `#exchange` (the socket round trip) is stubbed, so these run without a live daemon
# and pin the parts that actually encode the contract: request/response correlation,
# result unwrapping, error-code mapping, and the guards against the backend's
# silent no-op behaviours.
#
# The canned responses mirror what the live daemon was observed to return
# (see docs/dcommsctl-integration-plan.md, Step 0 / "Probe results").
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

  # --- request shape -----------------------------------------------------

  test "sends a JSON-RPC 2.0 request with a matching id" do
    stub_exchange(result: { "applications" => [] }) do
      @client.apps_list
    end

    request = @sent.last
    assert_equal "2.0", request["jsonrpc"]
    assert_equal "apps/list", request["method"]
    assert request["id"].present?, "request must carry an id"
  end

  test "omits params for parameterless methods" do
    stub_exchange(result: { "applications" => [] }) do
      @client.apps_list
    end

    refute @sent.last.key?("params")
  end

  test "defaults the url to the configured dcomms_url" do
    assert_equal "ws://localhost:6006/ws", DcommsClient.new.url
    assert_equal "ws://other.test:6006/ws", DcommsClient.new(url: "ws://other.test:6006/ws").url
  end

  # --- apps/list ---------------------------------------------------------

  test "apps_list unwraps the applications array into App objects" do
    result = { "applications" => [
      { "id" => "peertube", "name" => "Peertube", "version" => "", "redirect_uri" => "/tmp_redirect" },
      { "id" => "dawa", "name" => "DAWA", "version" => "0.0.1", "redirect_uri" => "/tmp_redirect" }
    ] }

    stub_exchange(result: result) do
      apps = @client.apps_list
      assert_equal 2, apps.size
      assert_equal "peertube", apps.first.id
      assert_equal "Peertube", apps.first.name
      # an empty version must NOT disqualify an app (the live catalog has them)
      assert_nil apps.first.version
      assert apps.first.available?
    end
  end

  test "apps_list drops rows missing both id and name" do
    result = { "applications" => [
      { "id" => "peertube", "name" => "Peertube", "version" => "", "redirect_uri" => "/tmp_redirect" },
      { "id" => "", "name" => "", "version" => "", "redirect_uri" => "" }
    ] }

    stub_exchange(result: result) do
      assert_equal [ "peertube" ], @client.apps_list.map(&:id)
    end
  end

  # --- error mapping -----------------------------------------------------

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

  # --- guards against silent no-ops --------------------------------------

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

  # --- jobs --------------------------------------------------------------

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
  end

  test "job_status treats done as success and running as non-terminal" do
    stub_exchange(result: { "id" => "j", "state" => "done", "exit_code" => 0 }) do
      assert @client.job_status(id: "j").success?
    end

    stub_exchange(result: { "id" => "j", "state" => "running" }) do
      refute @client.job_status(id: "j").terminal?
    end
  end

  test "job_log requests an offset and parses the chunk" do
    result = { "log" => "line\n", "next_offset" => 5, "eof" => false }

    stub_exchange(result: result) do
      chunk = @client.job_log(id: "j", offset: 0)
      assert_equal "line\n", chunk.log
      assert_equal 5, chunk.next_offset
      refute chunk.eof
      refute chunk.empty?
    end

    assert_equal({ "id" => "j", "offset" => 0 }, @sent.last["params"])
  end

  test "job_log tolerates the stubbed backend returning an empty log" do
    # `job/log` IS registered but returns an empty string today. That must parse
    # cleanly (it is indistinguishable on the wire from "no output yet").
    stub_exchange(result: { "log" => "" }) do
      chunk = @client.job_log(id: "j")
      assert chunk.empty?
      assert_equal 0, chunk.next_offset
      refute chunk.eof
    end
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

  test "instances_list parses instances, tolerating blank rows" do
    result = { "instances" => [
      { "id" => "peertube-quokka", "app" => "peertube", "domain" => "pt.test", "status" => "running" },
      { "id" => "" }
    ] }

    stub_exchange(result: result) do
      instances = @client.instances_list
      assert_equal 1, instances.size
      assert_equal "peertube-quokka", instances.first.id
      assert_equal "peertube", instances.first.app
    end
  end

  # --- protocol failures -------------------------------------------------

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
end
