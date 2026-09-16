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

  ##
  ## job/status (§B)
  ##

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

  ##
  ## job/log (§C)
  ##

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

  ##
  ## job/list (§D)
  ##

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

  ##
  ## inst/list (§E)
  ##

  test "apps_installed_list drops rows without an identity" do
    instances = @mock.apps_installed_list

    assert_equal %w[dawa-okapi peertube-quokka], instances.map(&:id).sort
    assert instances.all?(&:available?)
  end

  test "apps_installed_list exposes the fields the UI needs" do
    instance = @mock.apps_installed_list.find { |i| i.id == "peertube-quokka" }

    assert_equal "peertube", instance.catalog_entry_id
    assert_equal "peertube.test", instance.domain
    assert_equal "running", instance.status
    assert instance.running?
  end

  #
  # catalog entry detail
  #

  test "catalog_entry returns the fields the show page renders" do
    entry = @mock.catalog_entry(id: "peertube")

    assert_equal "peertube", entry.id
    assert_equal "Peertube", entry.name
    assert entry.available?
    assert entry.long_described?
    assert entry.upstream?
    assert entry.definition_linked?
    assert entry.updated?
  end

  test "catalog_entry's version matches its newest release" do
    # These two must not disagree: the header shows `version` while the release list is
    # ordered newest-first, and a mismatch would look like a data bug.
    entry = @mock.catalog_entry(id: "peertube")

    assert_equal entry.releases.first.version, entry.version
  end

  test "catalog_entry returns releases newest first" do
    entry = @mock.catalog_entry(id: "peertube")

    assert_equal %w[5.0.0 4.0.0 3.0.0 2.0.0 1.0.0], entry.releases.map(&:version)
    dates = entry.releases.map(&:released_at)
    assert_equal dates.sort.reverse, dates, "releases must be ordered newest first"
    assert entry.releases.all?(&:released?)
  end

  test "catalog_entry fixture covers single-release and multi-release entries" do
    # The show page has a release list and an empty-list branch, so the fixtures must
    # exercise both without hand-editing data.
    assert_equal 1, @mock.catalog_entry(id: "dawa").releases.size
    assert_equal 5, @mock.catalog_entry(id: "peertube").releases.size
  end

  test "catalog_entry is deterministic across instances" do
    # Faker is seeded per entry, so two mocks agree. Without this, screenshots and test
    # expectations would drift on every run.
    first = DcommsMock.new.catalog_entry(id: "peertube")
    second = DcommsMock.new.catalog_entry(id: "peertube")

    assert_equal first.long_description, second.long_description
    assert_equal first.releases.map(&:changelog), second.releases.map(&:changelog)
  end

  test "catalog_entry raises for an unknown id rather than returning a blank entry" do
    # Same rule as job/status: the backend must not invent state for something it never
    # had. A blank entry would render as "this app has no metadata".
    error = assert_raises(DcommsClient::ServerError) { @mock.catalog_entry(id: "nope") }

    assert_match(/unknown catalog entry/, error.message)
  end
end
