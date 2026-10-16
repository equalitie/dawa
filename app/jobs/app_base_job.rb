# Broadcast targets:
#                           stream id    target
#   broadcast_job_list      <app-id>     #app-jobs-list
#   broadcast_job_row       <app-id>     #<job.dom_id>
#   broadcast_app_box       <app-id>     #app-box
#   broadcast_app_card      "apps"       #app-card-<app-id>
#   broadcast_job_status    <job-id>     #job-status
#   broadcast_job_lines     <job-id>     #job-lines

class AppBaseJob < ApplicationJob
  include DcommsClientConcern

  def job
    @job ||= job_get(@job_id)
  end

  def app
    @app ||= app_get(@app_id)
  end

  ##
  ## broadcast helpers
  ##

  def broadcast_job_list(app: @app)
    stream_replace_to(app.id,
      target: "app-jobs-list",
      partial: "app_jobs/jobs_list",
      locals: { jobs: jobs_short_list(app), app: app })
    true
  end

  def broadcast_job_row(job: @job, app: @app)
    stream_replace_to(app.id,
      target: job.dom_id,
      partial: "app_jobs/job_row",
      locals: { job: job, app: app })
    true
  end

  def broadcast_app_box(app: @app, message: nil)
    stream_replace_to(app.id,
      target: "app-box",
      partial: "apps/box",
      locals: { app: app, message: message })
  end

  def broadcast_app_card(app: @app)
    stream_replace_to("apps",
      target: "app-card-#{app.id}",
      partial: "apps/card",
      locals: { app: app })
  end

  def broadcast_job_status(job_id, outcome, message)
    stream_replace_to(job_id,
      target: "job-status",
      partial: "app_jobs/status",
      locals: { outcome: outcome, message: message })
  end

  def broadcast_job_lines(job_id, text)
    stream_append_to(job_id,
      target: "job-lines",
      partial: "app_jobs/log_chunk",
      locals: { text: text })
  end

  #
  # Waiting for a dcommsctl job to finish.
  #
  # The daemon runs every mutation as a job and hands back its id, so "did it work?" is answered by
  # `job/status` and nothing else.
  #
  #   * COMPLETION IS `JobStatus#terminal?`, never inferred from the log. An empty chunk only
  #     means the cursor is caught up, and even `job/log`'s `finished` says the LOG ended, not
  #     whether the job succeeded; success and failure are `job/status`'s to report.
  #   * A RAISED `job/status` means the daemon has forgotten the job, which is not the same as "still
  #     running": it is returned as nil so the caller can stop instead of waiting for something that
  #     will never arrive.
  #   * WAITING IS BOUNDED, so a wedged job cannot hold a worker.
  #

  # Raised when the wait outlasted `MAX_DURATION`.
  class TimedOut < StandardError; end

  # How long to wait before asking again.
  POLL_INTERVAL = 0.2

  # Give up after this long and say so, rather than polling a wedged job forever. Matches the
  # daemon's own job timeout (`Conf.dcomms_job_timeout`).
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

      status = job_get(job_id)
      if status.nil? || status.terminal?
        return status
      elsif Time.current > deadline
        raise TimedOut
      end

      sleep POLL_INTERVAL
    end
  end

  private

  # Overridden by tests to start the wait already past its limit. nil in production, where
  # `MAX_DURATION` decides.
  def deadline_for_testing = nil
end
