#
# Waits for a start/stop command to finish, then reports the instance's new state.
#
# The analogue of ContainerJob, which polls `docker inspect` until the container reaches its target
# status. Apps differ in one decisive way: the daemon ALREADY gives us a job id and tracks the job
# in memory, whereas the only way to read an app's state (`inst/list`) shells out to
# `docker compose ps` for EVERY instance, each with its own 5 second timeout. So this waits on the
# job and reads `inst/list` once at the end, instead of polling the state.
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
  queue_as :default

  POLL_INTERVAL = 1.5

  # `compose up -d` can pull images and wait on healthchecks, so this is nowhere near the 30s
  # ContainerJob allows for a local docker start/stop. Matches the install job's ceiling.
  MAX_DURATION = 1.hour

  # @param job_id [String] dcommsctl's job id, from `inst/start` or `inst/stop`
  # @param instance_id [String] the instance the command was issued for
  def perform(job_id, instance_id)
    @job_id = job_id
    @instance_id = instance_id
    @deadline = deadline_for_testing || Time.current + MAX_DURATION

    loop do
      status = fetch_status
      # `job/status` raising means the daemon no longer knows the job (it restarted, or the job
      # aged out). There is nothing left to wait for, so report the state as it now stands rather
      # than hanging on it.
      return finish(nil) if status.nil?

      return finish(status.failed? ? status.error : nil) if status.terminal?
      return finish(I18n.t("apps.state.timeout")) if Time.current > @deadline

      sleep POLL_INTERVAL
    end
  rescue DcommsClient::Error => e
    finish(e.message)
  end

  private

  # Overridden by tests to start the job already past its limit. nil in production, where
  # `MAX_DURATION` decides.
  def deadline_for_testing = nil

  # nil when the daemon does not know the job (it raised), so the caller can stop waiting.
  def fetch_status
    adapter.job_status(id: @job_id)
  rescue DcommsClient::EmptyResult
    nil
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

  def adapter
    @adapter ||= DcommsAdapter.new
  end
end
