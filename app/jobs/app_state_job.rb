#
# Waits for a start/stop/restart command to finish, then reports the instance's new state.
#
# Restart is handled here, not by the daemon, which has no `inst/restart`.
#
class AppStateJob < AppBaseJob
  queue_as :default

  # called after the job has been initiated.
  #
  # @param job_id [String] dcommsctl's job id, from `inst/start`, `inst/stop`, or
  #   the stop half of a restart
  # @param instance_id [String] the instance the command was issued for
  # @param command [String] "start", "stop" or "restart".
  def perform(job_id:, app_id:, command:)
    @job_id = job_id.to_s
    @app_id = app_id.to_s
    @command = command.to_s

    broadcast_job_list(app: app)
    @job = wait_for_dcomms_job(@job_id)
    if @job.nil?
      finish
    elsif @job.failed?
      finish(@job.error)
    elsif @command == "restart"
      sleep 1
      start_again
    else
      finish
    end
  rescue AppBaseJob::TimedOut
    finish(I18n.t("apps.state.timeout"))
  rescue DcommsClient::Error => e
    finish(e.message)
  end

  private

  # run after a successful stop when the command is "restart"
  def start_again
    start_job_id = adapter.start(id: @app_id)
    broadcast_job_list(app: app)
    @job = wait_for_dcomms_job(start_job_id)
    @app = app_get(@app.id) # refresh status
    finish(@job&.failed? ? @job.error : nil)
  rescue AppBaseJob::TimedOut
    finish(I18n.t("apps.state.restart_timeout"))
  rescue DcommsClient::Error => e
    finish(e.message)
  end

  # job has finished or failed
  def finish(error = nil)
    if app.nil?
      broadcast_app_box(app: nil, message: error.presence || I18n.t("apps.state.gone", name: @app_id))
    else
      broadcast_app_box(app: app, message: error)
      broadcast_app_card(app: app)
      broadcast_job_row(app: app, job: job)
    end
  rescue DcommsClient::Error => e
    broadcast_app_box(app: app, message: e.message)
  end
end
