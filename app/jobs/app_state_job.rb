#
# Waits for a start/stop/restart command to finish, then reports the instance's new state.
#
# The analogue of ContainerJob, which polls `docker inspect` until the container reaches its target
# status. Apps differ in one decisive way: the daemon ALREADY gives us a job id and tracks the job
# in memory, whereas the only way to read an app's state (`inst/list`) shells out to
# `docker compose ps` for EVERY instance, each with its own 5 second timeout. So this waits on the
# job and reads `inst/list` once at the end, instead of polling the state.
#
# RESTART IS SEQUENCED HERE, not by the daemon, which has no `inst/restart`. It is a stop followed
# by a start: the stop job is waited on first, and only once it is terminal is the start issued.
#
# Broadcast targets:
#
#   the instance's stream   #app-box-<id>   -- the app's box, badge and buttons together
#   the "apps" stream       #app-card-<id>  -- the same app's card on the index
#
# The box is replaced whole rather than patching the badge and the buttons separately, because the
# two have to agree: a badge that says Running above a button that offers Start is worse than a
# page that is briefly stale.
#
class AppStateJob < ApplicationJob
  include WaitsForDcommsJob

  queue_as :default

  # @param job_id [String] dcommsctl's job id, from `inst/start`, `inst/stop`, or
  #   the stop half of a restart
  # @param instance_id [String] the instance the command was issued for
  # @param command [String] "start", "stop" or "restart". Defaults to a plain start/stop so an
  #   older enqueued job (from before restart existed) still runs.
  def perform(job_id, instance_id, command = nil)
    @instance_id = instance_id
    @command = command.to_s.presence || "start"

    status = wait_for_dcomms_job(job_id)

    # `job/status` raising means the daemon no longer knows the job (it restarted, or the job aged
    # out). There is nothing left to wait for, so report the state as it now stands rather than
    # hanging on it.
    return finish(nil) if status.nil?

    # A failed stop means the restart stops here: starting now would either be refused by the
    # lock or start on top of a container the stop could not bring down.
    return finish(status.error) if status.failed?

    if @command == "restart"
      # The stop half succeeded, so issue and wait on the start half the same way.
      restart_start
    else
      # A plain start or stop is done: the state it landed in is the report.
      finish(nil)
    end
  rescue WaitsForDcommsJob::TimedOut
    finish(I18n.t("apps.state.timeout"))
  rescue DcommsClient::Error => e
    finish(e.message)
  end

  private

  #
  # Issue the start half of a restart and wait for it.
  #
  # A failure to even issue the start (the daemon unreachable, or the lock still held) is reported
  # as the reason, which is what the box shows. The instance is stopped at this point, so saying so
  # is more useful than leaving the page claiming it is running.
  #
  def restart_start
    start_job_id = adapter.start(id: @instance_id)

    status = wait_for_dcomms_job(start_job_id)
    finish(status&.failed? ? status.error : nil)
  rescue WaitsForDcommsJob::TimedOut
    # The stop half already happened, so the instance is down: say the start did not complete
    # rather than reusing the generic timeout, which would imply nothing had changed.
    finish(I18n.t("apps.state.restart_timeout"))
  rescue DcommsClient::Error => e
    finish(e.message)
  end

  #
  # Report the instance as it now stands.
  #
  # `error` is why the command failed, when it did. The state is read either way: a failed command
  # still leaves the instance in some state, and the page should show that rather than keep the
  # in-flight spinner it was put into.
  #
  def finish(error)
    app = find_app
    # Someone removed the instance while the command ran: there is no state to report.
    return broadcast_box_message(error.presence || I18n.t("apps.state.gone", name: @instance_id)) if app.nil?

    stream_replace_to(@instance_id,
      target: "app-box-#{app.id}",
      partial: "apps/box",
      locals: { app: app, message: error })

    stream_replace_to("apps",
      target: "app-card-#{app.id}",
      partial: "apps/card",
      locals: { app: app })
  rescue DcommsClient::Error => e
    # The state could not be read -- the daemon went away between the job ending and this read.
    # There is nothing to render a box from, and `perform`'s own rescue cannot help here (a rescue
    # body is not covered by its own rescue), so the reason goes in the box's place. That also
    # clears the in-flight buttons, since it replaces the element they live in.
    broadcast_box_message(e.message)
  end

  # Replace the app's box with just a reason, keeping the id a later broadcast would target.
  def broadcast_box_message(message)
    stream_replace_to(@instance_id,
      target: "app-box-#{@instance_id}",
      partial: "apps/box_message",
      locals: { instance_id: @instance_id, message: message })
  end

  # The instance as `inst/list` reports it now, or nil when it is gone.
  def find_app
    adapter.apps_installed_list.find { |app| app.id == @instance_id }
  end
end
