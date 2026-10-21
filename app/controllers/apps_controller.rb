#
# Controller for dcomms backend app instances
#
class AppsController < BaseAdminController
  include DcommsClientConcern
  include LogsQueryConcern

  def index
    @apps = apps
  rescue DcommsClient::Error => e
    @apps = []
    @error = e.message
  end

  def show
    @app = app_get(params[:id])
    if @app.nil?
      head :not_found
    elsif params[:tab].nil?
      show_jobs
    elsif params[:tab] == "metrics"
      show_metrics
    elsif params[:tab] == "logs"
      show_logs
    end
  rescue DcommsClient::Error => e
    @error = e.message
    @jobs = []
  end

  #
  # GET /apps/:id/uninstall -- uninstall confirmation page
  #
  def uninstall
    @app = app_get(params[:id])
    @error = t("apps.uninstall.not_installed") if @app.nil?
  rescue DcommsClient::Error => e
    @app = nil
    @error = e.message
  end

  #
  # DELETE /apps/:id/uninstall -- remove the app.
  #
  def destroy
    @app = app_get(params[:app_id])

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

  # The commands the state buttons may ask for
  STATE_COMMANDS = %w[start stop restart].freeze

  #
  # PUT /apps/:id -- start, stop or restart an instance, per `params[:command]`.
  #
  def update
    command = params[:command].to_s
    return head :bad_request unless STATE_COMMANDS.include?(command)

    @app = app_get(params[:id])
    if @app.nil?
      # The instance is not in `inst/list`, so there is nothing to command. Render the reason and
      # stop: falling through to the render below would render twice and raise DoubleRenderError.
      return render_box(message: t("apps.uninstall.not_installed"))
    end

    job_id = adapter.public_send(command, id: @app.id)
    AppStateJob.perform_later(job_id: job_id, app_id: @app.id, command: command)
    render_box(command: command)
  rescue DcommsClient::Error => e
    render_box(message: e.message)
  end

  private

  def show_jobs
    all_jobs = jobs(@app)
    @jobs = jobs_short_list(@app)
    @show_more_jobs = all_jobs.size > @jobs.size
  end

  def show_metrics
    params[:window] ||= "day"
    @window = params[:window]
    filter = { dc_inst: @app.id }
    @metrics_charts = helpers.define_charts(
      keys: helpers.app_chart_names,
      window: @window,
      filter: filter
    )
  end

  def show_logs
    @filters = Logs::Filters.new(dc_inst: @app.id)
    @logs = fetch_logs(filters: @filters, cursor: nil)
    @cursor = newest_time(@logs)
  rescue VictoriaLogs::RequestError, Faraday::Error => e
    @logs = []
    @cursor = nil
    @error = e.message
  end

  def confirmation_matches?
    params[:confirm_id].to_s.strip == @app.id
  end

  def render_confirmation_error
    render :uninstall, status: :unprocessable_entity
  end

  #
  # Replace the box, with the command in flight and/or a reason.
  #
  # `command` may be nil (nothing in flight), and `message` may be nil (nothing to explain). The
  # `message` is passed through: an earlier version hardcoded `message: nil`, which dropped every
  # refusal reason before the user could read it.
  #
  def render_box(command: nil, message: nil)
    render turbo_stream: turbo_stream.replace(
      "app-box",
      partial: "apps/box", locals: { app: @app, pending: command, message: message }
    )
  end
end
