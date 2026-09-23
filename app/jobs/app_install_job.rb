#
# Follows an install job and streams its output to the browser.
#
# dcommsctl runs installs asynchronously and exposes the output only by polling: `job/log`
# returns a chunk from a byte offset, so "following" means repeatedly asking for what has
# appeared since the last read. This job does that in one place rather than in the browser,
# for three reasons:
#
#   * the daemon speaks JSON-RPC over a fresh WebSocket per call, and one server-side poller
#     is far cheaper than one per open tab;
#   * the log is fetched with a byte cursor, which is server-side state the browser should not
#     have to hold;
#   * the same broadcast can feed the modal now and the app's show page later.
#
# COMPLETION IS DECIDED BY `job/status`, NEVER BY THE LOG. A finished job's log becomes
# unreadable -- the daemon renames `.partial.log` to `.log` but keeps recording the old path -
# so treating a log error as "done" would end the stream early and lose the tail, and
# treating it as "keep going" would poll forever. `job/status` is the only honest signal.
#
class AppInstallJob < ApplicationJob
  queue_as :default

  # How long to wait before asking again. The install script sleeps between steps, so a
  # sub-second interval mostly returns nothing; the daemon's per-call timeout is 10s.
  POLL_INTERVAL = 1.5

  # Give up after this long and say so, rather than polling a wedged job forever. Matches the
  # daemon's own job timeout (Conf.dcomms_job_timeout).
  MAX_DURATION = 1.hour

  # A stream name unique to one job run.
  def self.stream_name(job_id)
    "app_install:#{job_id}"
  end

  def log(*msg)
    Rails.logger.info(msg.join(" "))
  end

  # @param job_id [String] dcommsctl's job id
  # @param instance_id [String] the instance the job belongs to; `job/log` needs BOTH
  def perform(job_id, instance_id)
    @job_id = job_id
    @instance_id = instance_id
    @offset = 0
    @deadline = deadline_for_testing || Time.current + MAX_DURATION

    loop do
      drain_log

      status = fetch_status
      # `job/status` raises for an unknown job, which means it is gone rather than running.
      # `I18n.t` rather than the view helper: a job has no ActionView context.
      return finish(:failed, I18n.t("jobs.install.status_unknown")) if status.nil?

      if status.terminal?
        # One more read before stopping: output written since the last poll is still
        # fetchable while the job is technically finished but the file has not been renamed
        # yet, and losing the final lines of a failed install is exactly when they matter.
        drain_log
        return finish(status.failed? ? :failed : :succeeded, status.error)
      end

      return finish(:timeout, nil) if Time.current > @deadline

      sleep POLL_INTERVAL
    end
  rescue DcommsClient::Error => e
    finish(:failed, e.message)
  end

  private

  # Overridden by tests to start the job already past its limit. nil in production, where
  # `MAX_DURATION` decides.
  def deadline_for_testing = nil

  # Read whatever output has appeared since the last offset, and broadcast it.
  #
  # Loops while chunks are not empty: the daemon caps a reply at 64KB, so a burst of output
  # needs several reads to catch up. `JobLog#eof` means "nothing more for now", not "the job
  # finished" -- see DcommsClient#job_log.
  def drain_log
    loop do
      chunk = adapter.job_log(id: @job_id, offset: @offset)
      log("API LOG CHUNK", chunk)
      break if chunk.log.empty?

      @offset = chunk.next_offset
      broadcast_lines(chunk.log)
      break if chunk.eof
    end
  rescue DcommsClient::Error => e
    # A log read failing while the job is still running is a real problem, but not a reason
    # to stop following: the daemon may be mid-rename. Record it and let `job/status` decide
    # the outcome, so the feed does not end on a transient read error.
    Rails.logger.warn "[AppInstallJob] log read failed for #{@job_id}: #{e.class}: #{e.message}"
  end

  # nil when the daemon does not know the job (it raised), so the caller can stop.
  def fetch_status
    adapter.job_status(id: @job_id)
  rescue DcommsClient::EmptyResult
    nil
  end

  def broadcast_lines(text)
    # `append` into the log pane. Rendered server-side so the client needs no JS: this is a
    # plain turbo stream target.
    stream_append_to(self.class.stream_name(@job_id),
      target: "install-log",
      partial: "app_installs/log_chunk",
      locals: { text: text })
  end

  def finish(outcome, message)
    stream_replace_to(self.class.stream_name(@job_id),
      target: "install-status",
      partial: "app_installs/status",
      locals: { outcome: outcome, message: message })
  end

  def adapter
    @adapter ||= DcommsAdapter.new
  end
end
