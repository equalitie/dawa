#
# Installing a catalog entry as a new app instance.
#
# This is a separate resource from AppsController rather than extra actions on it, because
# installing is its own three-step flow and `AppsController` is about instances that already
# exist:
#
#   new    (GET)  -> the form modal (choose a domain)
#   create (POST) -> call dcommsctl, then show the job-progress modal
#
# Both actions answer into `turbo_frame` "modal-frame" (rendered empty in the layout), which is
# what `v.remote_modal_button` targets.
#
# The progress modal is deliberately EPHEMERAL: it is keyed to nothing and does not survive a
# reload, so it needs no state of its own beyond the ids it was given. Refreshing the page
# lands on the catalog; the install continues in a background job regardless, and the result
# is visible on the app's show page once the instance appears in `inst/list`.
#
class AppInstallsController < BaseAdminController
  # GET /catalog/:id/install
  #
  # Renders the form. The catalog entry is looked up so the modal can name what is being
  # installed; a missing or unreachable entry renders that fact inside the modal rather than
  # failing the request, since the user already has the dialog open.
  def new
    @entry = catalog_entry
  rescue DcommsClient::Error => e
    @error = e.message
  end

  # POST /apps/install
  #
  # Starts the install and switches the modal to its progress view.
  #
  # The domain is required and is only lightly validated: caddy is not wired up yet, so the
  # value is recorded and passed to the daemon but does not yet route anything. Validating it
  # as a hostname now would reject nothing useful and could reject something valid later.
  def create
    @domain = params[:domain].to_s.strip

    if @domain.blank?
      return render_form(error: t("app_installs.domain_required"))
    end

    install_job = adapter.install(name: params[:app_id], domain: @domain)
    @job_id = install_job.job_id
    @app_id = install_job.instance_id
    AppInstallJob.perform_later(job_id: @job_id, app_id: @app_id)
  rescue DcommsClient::Error => e
    # A backend failure is terminal for this attempt: there is nothing to correct in the form,
    # so the dialog keeps the reason and drops the fields. The user closes and retries.
    @error = e.message
    render_progress_error
  end

  private

  # Where "Close" sends the user. The instance id comes from the install result, which the
  # daemon assigns; the app's show action looks the instance up by that id.
  def catalog_entry
    adapter.catalog_entry(id: params[:id])
  end

  def adapter
    @adapter ||= DcommsAdapter.new
  end

  #
  # Re-render the form with the reason it was rejected.
  #
  # Targets the INNER `install-dialog` frame, not the dialog itself. Replacing the whole
  # `modal-frame` would create a second Bootstrap modal while the first is still open, and the
  # two would stack (the old element is never disposed). Rewriting the frame's contents leaves
  # the modal element -- and its open state -- untouched.
  #
  # The entry has to be looked up again: `create` only received `app_id`, and the form needs
  # the entry to name what is being installed and to carry the id forward. A failure to look
  # it up is itself reported, so the user is never left with a form that cannot submit.
  #
  def render_form(error:)
    @error = error
    @entry = adapter.catalog_entry(id: params[:app_id])
  rescue DcommsClient::Error => e
    @entry = nil
    @error = e.message
  ensure
    render turbo_stream: turbo_stream.update("install-dialog", partial: "app_installs/form")
  end

  def render_progress_error
    render turbo_stream: turbo_stream.update("modal-frame", partial: "app_installs/error")
  end
end
