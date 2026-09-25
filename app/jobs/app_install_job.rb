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
# Waiting for the job to end is `WaitsForDcommsJob`'s business; what is specific to an install is
# the log feed and what its outcomes are called.
#
class AppInstallJob < ApplicationJob
  include WaitsForDcommsJob

  queue_as :default

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

    status = wait_for_dcomms_job(job_id) { drain_log }

    # `job/status` raising for an unknown job means it is gone rather than running.
    # `I18n.t` rather than the view helper: a job has no ActionView context.
    return finish(:failed, I18n.t("jobs.install.status_unknown")) if status.nil?

    # One more read before stopping: output written between the last poll and the job ending is
    # still there to fetch, and losing the final lines of a failed install is exactly when they
    # matter.
    drain_log

    finish(status.failed? ? :failed : :succeeded, status.error)
  rescue WaitsForDcommsJob::TimedOut
    finish(:timeout, nil)
  rescue DcommsClient::Error => e
    finish(:failed, e.message)
  end

  private

  # Read whatever output has appeared since the last offset, and broadcast it.
  #
  # Loops while chunks are not empty: the daemon caps a reply at 64KB, so a burst of output
  # needs several reads to catch up. `JobLog#finished` reports that the log has ENDED, so the loop
  # can stop on the daemon's word; an empty chunk with `finished: false` only means there is
  # nothing new YET -- see DcommsClient#job_log.
  def drain_log
    loop do
      chunk = adapter.job_log(id: @job_id, offset: @offset)
      log("API LOG CHUNK", chunk)
      break if chunk.log.empty?

      @offset = chunk.next_offset
      broadcast_lines(chunk.log)
      break if chunk.finished
    end
  rescue DcommsClient::Error => e
    # A log read failing while the job is still running is a real problem, but not a reason
    # to stop following: the daemon may be mid-rename. Record it and let `job/status` decide
    # the outcome, so the feed does not end on a transient read error.
    Rails.logger.warn "[AppInstallJob] log read failed for #{@job_id}: #{e.class}: #{e.message}"
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
end
