require "test_helper"

#
# Tests for the temporary dcommsctl mock.
#
# These pin the two things that make the mock useful: it must honour the INTENDED
# contract (shapes and semantics from docs/dcommsctl-api-requests.md), and it must be
# driveable deterministically so DcommsJob's polling loop can be tested.
#
class DcommsMockTest < ActiveSupport::TestCase
  setup do
    @mock = DcommsMock.new
  end

  # --- job/status (§B) ---------------------------------------------------

  test "job_status advances through pending to a terminal state" do
    @mock.script_job(id: "j2", running_for: 2)

    # running_for: 2 means two polls in "running" before reaching the terminal state.
    assert_equal "running", @mock.job_status(id: "j2").state
    assert_equal "running", @mock.job_status(id: "j2").state
    assert_equal "done", @mock.job_status(id: "j2").state
    assert @mock.job_status(id: "j2").terminal?
    assert @mock.job_status(id: "j2").success?
  end

  test "job_status reports a failed job with exit code and message" do
    @mock.script_job(id: "bad", running_for: 0, terminal_state: "failed", exit_code: 2,
                     error: "compose up failed")

    status = @mock.job_status(id: "bad")

    assert status.terminal?
    assert status.failed?
    assert_equal 2, status.exit_code
    assert_equal "compose up failed", status.error
  end

  test "job_status raises for an unknown job rather than inventing state" do
    assert_raises(DcommsClient::ServerError) { @mock.job_status(id: "nope") }
  end

  # --- job/log (§C) ------------------------------------------------------

  test "job_log serves chunks incrementally and advances the offset" do
    @mock.script_job(id: "j1", chunks: [ "one\n", "two\n" ])

    first = @mock.job_log(id: "j1", offset: 0)
    assert_equal "one\n", first.log
    assert_equal 4, first.next_offset

    second = @mock.job_log(id: "j1", offset: first.next_offset)
    assert_equal "two\n", second.log
    assert_equal 8, second.next_offset

    third = @mock.job_log(id: "j1", offset: second.next_offset)
    assert third.empty?, "caught up means an empty chunk"
    assert_equal 8, third.next_offset
  end

  test "job_log tolerates a partial final line" do
    @mock.script_job(id: "j1", chunks: [ "no newline here" ])

    chunk = @mock.job_log(id: "j1", offset: 0)

    assert_equal "no newline here", chunk.log
    refute chunk.log.end_with?("\n")
  end

  test "job_log does not rewind a client that is behind" do
    @mock.script_job(id: "j1", chunks: [ "one\n", "two\n" ])
    @mock.job_log(id: "j1", offset: 0)

    behind = @mock.job_log(id: "j1", offset: 0)

    assert behind.empty?
    assert_equal 4, behind.next_offset, "should report where the client actually is"
  end

  test "job_log eof means caught up, not finished" do
    @mock.script_job(id: "j1", chunks: [], running_for: 5)

    chunk = @mock.job_log(id: "j1", offset: 0)

    assert chunk.empty?
    assert chunk.eof
    refute @mock.job_status(id: "j1").terminal?, "eof must not imply completion"
  end

  # --- job/list (§D) -----------------------------------------------------

  test "job_list filters by instance and by active state" do
    @mock.script_job(id: "a", instance_id: "inst-1", running_for: 5)
    @mock.script_job(id: "b", instance_id: "inst-2", running_for: 5)

    assert_equal %w[a b], @mock.job_list.map(&:id)
    assert_equal [ "a" ], @mock.job_list(instance_id: "inst-1").map(&:id)
    # neither job has advanced yet, so both are non-terminal and active
    assert_equal %w[a b], @mock.job_list(active_only: true).map(&:id)
  end

  test "job_list excludes jobs that reached a terminal state" do
    @mock.script_job(id: "done-job", running_for: 0, terminal_state: "done")
    @mock.job_status(id: "done-job") # drive it terminal

    assert_empty @mock.job_list(active_only: true)
    assert_equal [ "done-job" ], @mock.job_list.map(&:id)
  end

  # --- inst/list (§E) ----------------------------------------------------

  test "instances_list drops rows without an identity" do
    instances = @mock.instances_list

    assert_equal %w[dawa-okapi peertube-quokka], instances.map(&:id).sort
    assert instances.all?(&:available?)
  end

  test "instances_list exposes the fields the UI needs" do
    instance = @mock.instances_list.find { |i| i.id == "peertube-quokka" }

    assert_equal "peertube", instance.app
    assert_equal "peertube.test", instance.domain
    assert_equal "running", instance.status
  end
end
