#
# Waiting for a dcommsctl job to finish.
#
# The daemon runs every mutation as a job and hands back its id, so "did it work?" is answered by
# `job/status` and nothing else. That is a small protocol with several traps in it, and this is
# where they live so each job does not re-learn them:
#
#   * COMPLETION IS `JobStatus#terminal?`, never inferred from the log. An empty chunk only
#     means the cursor is caught up, and even `job/log`'s `finished` says the LOG ended, not
#     whether the job succeeded; success and failure are `job/status`'s to report.
#   * A RAISED `job/status` means the daemon has forgotten the job, which is not the same as "still
#     running": it is returned as nil so the caller can stop instead of waiting for something that
#     will never arrive.
#   * WAITING IS BOUNDED, so a wedged job cannot hold a worker.
#
# The caller owns the OUTCOME: this models only the wait, because what a finished job means differs
# per job (an install reports the daemon's error text, a state change re-reads the instance and
# re-renders it).
#
module WaitsForDcommsJob
  extend ActiveSupport::Concern

  # Raised when the wait outlasted `MAX_DURATION`. Its own class rather than a flag, so a job can
  # `rescue` the timeout instead of carrying a fourth branch through its loop, and so it cannot be
  # mistaken for a `DcommsClient::Error` (which means the backend could not be asked at all).
  class TimedOut < StandardError; end

  # How long to wait before asking again. Both users follow jobs whose scripts sleep between steps,
  # so a sub-second interval mostly returns nothing; the daemon's per-call timeout is 10s.
  POLL_INTERVAL = 1.5

  # Give up after this long and say so, rather than polling a wedged job forever. Matches the
  # daemon's own job timeout (`Conf.dcomms_job_timeout`), and is generous on purpose: `compose up
  # -d` can pull images and wait on healthchecks, so the 30s ContainerJob allows itself for a local
  # docker start/stop would be far too short here.
  MAX_DURATION = 1.hour

  #
  # Wait for `job_id` to finish.
  #
  # The block is called once per poll, BEFORE the status is read, which is where an install drains
  # its log to catch up. It is called for the final poll too, so a caller wanting one last read
  # AFTER the job ends has to do that itself.
  #
  # @param job_id [String] dcommsctl's job id
  # @return [Dcomms::JobStatus, nil] the terminal status, or nil when the daemon does not know the
  #   job at all
  # @raise [TimedOut] when the wait outlasted `MAX_DURATION`
  #
  def wait_for_dcomms_job(job_id)
    deadline = deadline_for_testing || Time.current + MAX_DURATION

    loop do
      yield if block_given?

      status = dcomms_job_status(job_id)
      return status if status.nil? || status.terminal?

      raise TimedOut if Time.current > deadline

      sleep POLL_INTERVAL
    end
  end

  private

  # Overridden by tests to start the wait already past its limit. nil in production, where
  # `MAX_DURATION` decides.
  def deadline_for_testing = nil

  # nil when the daemon does not know the job (it raised), so the caller can stop waiting.
  def dcomms_job_status(job_id)
    adapter.job_status(id: job_id)
  rescue DcommsClient::EmptyResult
    nil
  end

  def adapter
    @adapter ||= DcommsAdapter.new
  end
end
