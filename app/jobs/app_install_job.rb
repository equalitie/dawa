#
# Follows an install job and streams its output to the browser.
#
# dcommsctl runs installs asynchronously and exposes the output only by polling: `job/log`
# returns a chunk from a byte offset, so "following" means repeatedly asking for what has
# appeared since the last read. This job does that in one place rather than in the browser,
# for three reasons:
#
#
class AppInstallJob < AppBaseJob
  queue_as :default

  def log(*msg)
    Rails.logger.info(msg.join(" "))
  end

  # @param job_id [String] dcommsctl's job id
  # @param instance_id [String] the instance the job belongs to; `job/log` needs BOTH
  def perform(job_id:, app_id:)
    @job_id = job_id.to_s
    @app_id = app_id.to_s
    @offset = 0

    status = wait_for_dcomms_job(job_id) { drain_log }
    if status.nil?
      finish(:failed, I18n.t("jobs.install.status_unknown"))
    else
      # One more read before stopping: output written between the last poll and the job ending is
      # still there to fetch, and losing the final lines of a failed install is exactly when they
      # matter.
      drain_log
      finish(status.failed? ? :failed : :succeeded, status.error)
    end
  rescue AppBaseJob::TimedOut
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
      broadcast_job_lines(@job_id, chunk.log)
      break if chunk.finished
    end
  rescue DcommsClient::Error => e
    # A log read failing while the job is still running is a real problem, but not a reason
    # to stop following: the daemon may be mid-rename. Record it and let `job/status` decide
    # the outcome, so the feed does not end on a transient read error.
    Rails.logger.warn "[AppInstallJob] log read failed for #{@job_id}: #{e.class}: #{e.message}"
  end

  def finish(outcome, message)
    broadcast_job_status(@job_id, outcome, message)
  end
end
