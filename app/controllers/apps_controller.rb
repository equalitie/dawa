#
# Controller for dcomms backend app instances
#
class AppsController < BaseAdminController
  def index
    @apps = apps
  rescue DcommsClient::Error => e
    @apps = []
    @error = e.message
  end

  def show
    @app = find_app(params[:id])
    # A missing instance is a 404, not an empty page
    return head :not_found if @app.nil?

    all_jobs = jobs(active_only: false)
    @active_jobs, @past_jobs = partition_jobs(all_jobs)
  rescue DcommsClient::Error => e
    @error = e.message
    @active_jobs = []
    @past_jobs = []
  end

  #
  # GET /apps/:id/uninstall -- uninstall confirmation page
  #
  def uninstall
    @app = find_app(params[:id])
    @error = t("apps.uninstall.not_installed") if @app.nil?
  rescue DcommsClient::Error => e
    @app = nil
    @error = e.message
  end

  #
  # DELETE /apps/:id/uninstall -- remove the app.
  #
  #
  def destroy
    @app = find_app(params[:app_id])

    if @app.nil?
      @error = t("apps.uninstall.not_installed")
      return render_confirmation_error
    end

    unless confirmation_matches?
      @error = t("apps.uninstall.name_mismatch", name: @app.id)
      return render_confirmation_error
    end

    adapter.uninstall(id: @app.id)

    redirect_to apps_path, notice: t("apps.uninstall.started", name: @app.id)
  rescue DcommsClient::Error => e
    # The daemon refused it: unreachable, or another job holds the instance's lock. The page keeps
    # the reason and the field, so the user can read it and retry once the lock is free.
    @error = e.message
    render_confirmation_error
  end

  #
  # The commands the state buttons may ask for. A whitelist rather than dispatching
  # `params[:command]` straight at the adapter: only these two are meaningful, and naming them
  # here keeps the request from reaching anything else on the adapter.
  #
  STATE_COMMANDS = %w[start stop].freeze

  #
  # PUT /apps/:id -- start or stop an instance, per `params[:command]`.
  #
  def update
    command = params[:command].to_s
    # Unreachable from the buttons, which only ever send the two names above; answered without a
    # body because there is nothing to say to a caller that invented one.
    return head :bad_request unless STATE_COMMANDS.include?(command)

    app = find_app(params[:id])
    # Nothing to start or stop: the instance is not in `inst/list`. The message goes into the box's
    # slot, which also clears any in-flight button, since it replaces the element they live in.
    return render_box_message(params[:id], t("apps.uninstall.not_installed")) if app.nil?

    job_id = adapter.public_send(command, id: app.id)
    AppStateJob.perform_later(job_id, app.id)

    # The pressed button becomes a disabled spinner and the other one is disabled
    render turbo_stream: turbo_stream.replace(
      "app-box-#{app.id}",
      partial: "apps/box", locals: { app: app, pending: command }
    )
  rescue DcommsClient::Error => e
    # The daemon refused it, or the lookup itself failed. Either way the page has to be told,
    # because nothing navigates.
    if app.nil?
      render_box_message(params[:id], e.message)
    else
      render turbo_stream: turbo_stream.replace(
        "app-box-#{app.id}",
        partial: "apps/box", locals: { app: app, message: e.message }
      )
    end
  end

  private

  # True when the user typed name matches the instance in the url.
  def confirmation_matches?
    params[:confirm_id].to_s.strip == @app.id
  end

  def render_confirmation_error
    render :uninstall, status: :unprocessable_entity
  end

  #
  # Replace an app's box with just the reason, for the case where there is no app to describe.
  #
  # The replacement carries the same id (`apps/box_message` puts it on the element) because the
  # element it replaces is what later broadcasts target.
  #
  def render_box_message(instance_id, message)
    render turbo_stream: turbo_stream.replace(
      "app-box-#{instance_id}",
      partial: "apps/box_message", locals: { instance_id: instance_id, message: message }
    )
  end

  # Split the jobs for one instance into in-flight and finished.
  def partition_jobs(jobs)
    jobs.partition { |job| !job.terminal? }
  end

  def apps
    adapter.apps_installed_list
  end

  def find_app(id)
    apps.find { |app| app.id == id.to_s }
  end

  def jobs(active_only:)
    adapter.job_list(instance_id: params[:id], active_only: active_only)
  end

  # Never talk to DcommsClient directly; the adapter owns the real/mock decision.
  def adapter
    @adapter ||= DcommsAdapter.new
  end
end
