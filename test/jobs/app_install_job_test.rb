require_relative "../test_helper"

#
# Tests for the install-following job.
#
# The adapter is stubbed, so these run without dcommsctl. What matters here is the loop's
# contract: it advances a byte cursor, it decides completion from `job/status` alone, it does
# a final read so the tail is not lost, and it always terminates.
#
class AppInstallJobTest < ActiveSupport::TestCase
  # A scripted adapter: yields one status per poll, and serves log chunks by offset.
  #
  # `statuses` is consumed one per call and the LAST one repeats, so a test can say "running,
  # running, done" without having to predict the exact number of polls.
  class FakeAdapter
    attr_reader :log_calls, :status_calls

    def initialize(statuses:, chunks: {}, log_raises_after: nil)
      @statuses = statuses
      @chunks = chunks
      @log_raises_after = log_raises_after
      @log_calls = []
      @status_calls = 0
    end

    def job_status(id:)
      @status_calls += 1
      spec = @statuses[@status_calls - 1] || @statuses.last
      raise DcommsClient::EmptyResult, "unknown job #{id}" if spec == :unknown

      Dcomms::JobStatus.new(**{ id: id, state: "running" }.merge(spec))
    end

    def job_log(id:, offset: 0)
      @log_calls << offset
      raise DcommsClient::ServerError.new(code: -32603, message: "no such file") if
        @log_raises_after && @log_calls.size > @log_raises_after

      text = @chunks[offset].to_s
      # The fake reports the log FINISHED once it has nothing more to hand over, which is what the
      # daemon says when its cursor reaches the end of a log whose job has ended.
      Dcomms::JobLog.new(log: text, next_offset: offset + text.bytesize, finished: text.empty?)
    end
  end

  # Run the job with the fake adapter and the poll interval squashed, so tests do not sleep.
  #
  # `deadline:` lets a test start the job already past its time limit; the default keeps the
  # real one.
  def run_job(adapter, job_id: "install-1", instance_id: "peertube-zebu", deadline: nil)
    job = AppInstallJob.new
    job.define_singleton_method(:adapter) { adapter }
    job.define_singleton_method(:sleep) { |_| }
    job.define_singleton_method(:deadline_for_testing) { deadline } if deadline
    broadcasts = []
    job.define_singleton_method(:stream_append_to) do |stream, target:, partial:, locals:|
      broadcasts << [ :append, stream, target, locals[:text] ]
    end
    job.define_singleton_method(:stream_replace_to) do |stream, target:, partial:, locals:|
      broadcasts << [ :replace, stream, target, locals ]
    end
    job.perform(job_id, instance_id)
    broadcasts
  end

  def status_broadcasts(broadcasts)
    broadcasts.select { |kind, _| kind == :replace }
  end

  ##
  ## reading the log
  ##

  test "it reads from offset 0 and advances by the bytes received" do
    adapter = FakeAdapter.new(
      statuses: [ { state: "done" } ],
      chunks: { 0 => "one\n", 4 => "two\n" }
    )

    run_job(adapter)

    # 0 then 4, then 8 twice: the cursor only moves by bytes actually received, so no offset
    # is ever read twice with data -- re-reading from an earlier offset would duplicate output
    # in the pane. The repeated 8 is the deliberate final read once the status is terminal.
    assert_equal [ 0, 4, 8, 8 ], adapter.log_calls
  end

  test "it broadcasts each chunk as it arrives" do
    adapter = FakeAdapter.new(
      statuses: [ { state: "done" } ],
      chunks: { 0 => "one\n", 4 => "two\n" }
    )

    broadcasts = run_job(adapter)
    appended = broadcasts.select { |kind, _| kind == :append }.map(&:last)

    assert_equal [ "one\n", "two\n" ], appended
  end

  test "it drains several chunks before checking status again" do
    # The daemon caps a reply at 64KB, so a burst of output needs repeated reads. Polling
    # status between each would make catching up needlessly slow.
    adapter = FakeAdapter.new(
      statuses: [ { state: "done" } ],
      chunks: { 0 => "a", 1 => "b", 2 => "c" }
    )

    run_job(adapter)

    assert_equal 1, adapter.status_calls
    # Four reads: a, b, c, then the empty final read at offset 3.
    assert_equal [ 0, 1, 2, 3, 3 ], adapter.log_calls
  end

  ##
  ## deciding when to stop
  ##

  test "it stops as soon as the status is terminal" do
    adapter = FakeAdapter.new(statuses: [ { state: "running" }, { state: "done" } ])

    run_job(adapter)

    assert_equal 2, adapter.status_calls
  end

  test "a successful job reports success" do
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ])

    outcome = status_broadcasts(run_job(adapter)).last.last

    assert_equal :succeeded, outcome[:outcome]
  end

  test "a failed job reports the daemon's error" do
    adapter = FakeAdapter.new(statuses: [ { state: "failed", error: "port in use" } ])

    outcome = status_broadcasts(run_job(adapter)).last.last

    assert_equal :failed, outcome[:outcome]
    assert_equal "port in use", outcome[:message]
  end

  test "it reads the log one final time after the job is terminal" do
    # Regression guard for the tail: output written between the last poll and the job
    # finishing is still fetchable, and losing the final lines of a failed install is exactly
    # when they matter most.
    adapter = FakeAdapter.new(
      statuses: [ { state: "done" } ],
      chunks: { 0 => "first\n", 6 => "last gasp\n" }
    )

    broadcasts = run_job(adapter)
    appended = broadcasts.select { |kind, _| kind == :append }.map(&:last)

    assert_equal [ "first\n", "last gasp\n" ], appended
  end

  test "a job the daemon no longer knows ends the loop" do
    # `job/status` raises for an unknown id. Treating that as "keep polling" would spin
    # forever; it has to end the job.
    adapter = FakeAdapter.new(statuses: [ :unknown ])

    outcome = status_broadcasts(run_job(adapter)).last.last

    assert_equal :failed, outcome[:outcome]
    assert_not_nil outcome[:message]
  end

  ##
  ## failure modes
  ##

  test "a failing log read does not end the loop while the job is still running" do
    # A read can fail transiently (the daemon mid-rename). Only job/status decides the
    # outcome, so the stream keeps following rather than ending on a read error.
    adapter = FakeAdapter.new(
      statuses: [ { state: "running" }, { state: "done" } ],
      chunks: { 0 => "out\n" },
      log_raises_after: 1
    )

    outcome = status_broadcasts(run_job(adapter)).last.last

    assert_equal :succeeded, outcome[:outcome]
  end

  test "an unreachable daemon ends the loop and reports it" do
    adapter = Class.new do
      def job_status(id:)
        raise DcommsClient::ConnectionError, "no route to host"
      end

      def job_log(**) = raise(DcommsClient::ConnectionError, "no route to host")
    end.new

    outcome = status_broadcasts(run_job(adapter)).last.last

    assert_equal :failed, outcome[:outcome]
    assert_match(/no route to host/, outcome[:message])
  end

  test "it gives up after the maximum duration rather than polling forever" do
    # A wedged job must not leave the feed (and the worker) hanging indefinitely.
    adapter = FakeAdapter.new(statuses: [ { state: "running" } ])

    broadcasts = run_job(adapter, deadline: 1.second.ago)

    assert_equal :timeout, status_broadcasts(broadcasts).last.last[:outcome]
  end

  ##
  ## the stream name
  ##

  test "the chunk partial preserves newlines exactly" do
    # The pane is a <pre>, so whitespace is significant. A chunk can also end mid-line (the
    # daemon caps replies at 64KB), so nothing here may split or reformat the text: any
    # inserted newline would appear in the output that was not printed.
    vc = ApplicationController.new.view_context

    assert_equal "<span class=\"install-log-chunk\">a\nb</span>\n",
                 vc.render(partial: "app_installs/log_chunk", locals: { text: "a\nb" })
  end

  test "the stream name is scoped to the job" do
    # Two installs running at once must not broadcast into each other's dialog.
    assert_equal "app_install:install-1", AppInstallJob.stream_name("install-1")
    refute_equal AppInstallJob.stream_name("install-1"), AppInstallJob.stream_name("install-2")
  end
end
